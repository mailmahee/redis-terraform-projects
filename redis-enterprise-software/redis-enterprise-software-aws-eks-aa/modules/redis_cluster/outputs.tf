output "cluster_name" {
  description = "Name of the Redis Enterprise cluster"
  value       = var.cluster_name
}

output "cluster_namespace" {
  description = "Kubernetes namespace of the Redis Enterprise cluster"
  value       = var.namespace
}

output "admin_credentials_secret_name" {
  description = "Name of the Kubernetes secret containing admin credentials"
  value       = kubernetes_secret.redis_enterprise_admin.metadata[0].name
}

output "node_count" {
  description = "Number of nodes in the Redis Enterprise cluster"
  value       = var.node_count
}
