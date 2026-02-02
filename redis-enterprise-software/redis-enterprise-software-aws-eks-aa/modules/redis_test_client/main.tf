#==============================================================================
# Redis Test Client - Simple Single Container
#==============================================================================
# Ubuntu container with redis-cli, redis-benchmark, and memtier_benchmark
# All installed via apt - super simple!
#==============================================================================

resource "kubernetes_deployment" "redis_test_client" {
  metadata {
    name      = var.deployment_name
    namespace = var.namespace
    labels = {
      app     = "redis-test-client"
      purpose = "testing"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "redis-test-client"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis-test-client"
        }
      }

      spec {
        container {
          name  = "redis-client"
          image = "ubuntu:22.04"

          # Install tools and keep running
          command = ["/bin/bash", "-c"]
          args = [
            <<-EOT
            apt-get update
            apt-get install -y curl gnupg lsb-release
            curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" > /etc/apt/sources.list.d/redis.list
            apt-get update
            apt-get install -y redis-tools memtier-benchmark
            echo "All tools installed successfully!"
            redis-cli --version
            memtier_benchmark --version
            while true; do sleep 3600; done
            EOT
          ]

          # Environment variables for easy access
          env {
            name  = "REDIS_HOST"
            value = var.redis_host
          }

          env {
            name  = "REDIS_PORT"
            value = tostring(var.redis_port)
          }

          env {
            name  = "REDIS_PASSWORD"
            value = var.redis_password
          }

          # Resource limits (t3.micro equivalent)
          resources {
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
            limits = {
              cpu    = var.cpu_limit
              memory = var.memory_limit
            }
          }
        }
      }
    }
  }

  depends_on = [var.redis_cluster_ready]
}

# Optional: ConfigMap with helper scripts
resource "kubernetes_config_map" "test_scripts" {
  count = var.create_test_scripts ? 1 : 0

  metadata {
    name      = "${var.deployment_name}-scripts"
    namespace = var.namespace
  }

  data = {
    "test-connection.sh" = <<-EOT
      #!/bin/bash
      echo "Testing Redis connection..."
      redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD ping
      EOT

    "run-benchmark.sh" = <<-EOT
      #!/bin/bash
      echo "Running redis-benchmark..."
      redis-benchmark -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD -t set,get -n 10000 -c 10
      EOT

    "run-memtier.sh" = <<-EOT
      #!/bin/bash
      echo "Running memtier_benchmark..."
      memtier_benchmark --server=$REDIS_HOST --port=$REDIS_PORT -a $REDIS_PASSWORD \
        --protocol=redis --clients=10 --threads=2 --ratio=1:10 \
        --data-size=32 --key-pattern=R:R --requests=10000
      EOT
  }
}
