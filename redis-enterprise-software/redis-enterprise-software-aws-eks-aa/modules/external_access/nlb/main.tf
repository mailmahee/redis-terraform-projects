#==============================================================================
# NLB External Access - Kubernetes LoadBalancer Services
#==============================================================================
# Creates AWS Network Load Balancers for external access by patching service types
#==============================================================================

# Data source to get existing Redis Enterprise UI service
data "kubernetes_service" "redis_ui" {
  count = var.expose_ui ? 1 : 0

  metadata {
    name      = var.redis_ui_service_name
    namespace = var.namespace
  }
}

# Patch Redis Enterprise UI service to LoadBalancer type
resource "kubernetes_service_v1" "redis_ui_external" {
  count = var.expose_ui ? 1 : 0

  metadata {
    name      = "${var.redis_ui_service_name}-external"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
    }
    labels = merge(
      {
        "app.kubernetes.io/component"  = "redis-enterprise-ui"
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.tags
    )
  }

  spec {
    type = "LoadBalancer"

    selector = data.kubernetes_service.redis_ui[0].spec[0].selector

    port {
      name        = "https"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }

    session_affinity = "ClientIP"
  }

  wait_for_load_balancer = true
}

# Create LoadBalancer services for Redis databases
resource "kubernetes_service_v1" "redis_db_external" {
  for_each = var.expose_databases ? var.redis_db_services : {}

  metadata {
    name      = "${each.value.service_name}-external"
    namespace = var.namespace
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"                            = "internet-facing"
      "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
    }
    labels = merge(
      {
        "app.kubernetes.io/component"  = "redis-database"
        "app.kubernetes.io/name"       = each.key
        "app.kubernetes.io/managed-by" = "terraform"
      },
      var.tags
    )
  }

  spec {
    type = "LoadBalancer"

    selector = {
      "redis.io/database" = each.key
    }

    port {
      name        = "redis"
      port        = each.value.port
      target_port = each.value.port
      protocol    = "TCP"
    }

    session_affinity = "None" # Redis clients handle connection pooling
  }

  wait_for_load_balancer = true
}
