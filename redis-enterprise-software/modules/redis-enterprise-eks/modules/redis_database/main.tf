#==============================================================================
# REDIS ENTERPRISE DATABASE (REDB)
#==============================================================================

resource "kubectl_manifest" "redis_database" {
  count = var.create_database ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1alpha1
    kind: RedisEnterpriseDatabase
    metadata:
      name: ${var.database_name}
      namespace: ${var.namespace}
    spec:
      # Reference to the Redis Enterprise cluster
      redisEnterpriseCluster:
        name: ${var.cluster_name}

      # Database size
      memorySize: ${var.memory_size}
${var.enable_redis_flex ? "\n      # Redis Flex (Auto Tiering) configuration\n      isRof: true\n      rofRamSize: ${var.rof_ram_size}" : ""}

      # Database type
      databaseType: redis

      # Database port
      databasePort: ${var.database_port}

      ${var.database_service_port > 0 ? "# Custom service port for external access\n      databaseServicePort: ${var.database_service_port}" : ""}

      # Replication (HA enabled by default)
      replication: ${var.replication}

      # Sharding configuration (1 shard by default)
      ${var.shard_count > 1 ? "shardCount: ${var.shard_count}" : ""}

      # Persistence
      persistence: ${var.persistence}

      # Database password (optional)
      ${var.database_password != "" ? "databaseSecretName: ${kubernetes_secret.redis_database_password[0].metadata[0].name}" : ""}

      # TLS configuration
      tlsMode: ${var.tls_mode}

      ${length(var.client_authentication_certificates) > 0 ? "# Client certificate authentication\n      clientAuthenticationCertificates:\n${join("\n", [for cert in var.client_authentication_certificates : "        - ${cert}"])}" : ""}

      # Service type for database access
      databaseServiceType: ${var.database_service_type}

      # Eviction policy
      evictionPolicy: ${var.eviction_policy}

      ${var.redis_version != "" ? "# Redis OSS version\n      redisVersion: \"${var.redis_version}\"" : ""}

      ${length(var.modules_list) > 0 ? "# Redis modules\n      modulesList:\n${join("\n", [for mod in var.modules_list : "        - name: ${mod.name}\n          version: ${mod.version}"])}" : ""}
  YAML

  depends_on = [
    var.cluster_ready
  ]
}

#==============================================================================
# DATABASE PASSWORD SECRET (if password provided)
#==============================================================================

resource "kubernetes_secret" "redis_database_password" {
  count = var.create_database && var.database_password != "" ? 1 : 0

  metadata {
    name      = "${var.database_name}-password"
    namespace = var.namespace
  }

  # Kubernetes secrets with 'data' field are automatically base64 encoded by Terraform
  type = "Opaque"

  data = {
    password = var.database_password
  }
}

#==============================================================================
# WAIT FOR DATABASE TO BE READY
#==============================================================================

resource "time_sleep" "wait_for_database" {
  count = var.create_database ? 1 : 0

  depends_on = [kubectl_manifest.redis_database[0]]

  create_duration = "60s" # Wait 1 minute for database to become active
}
