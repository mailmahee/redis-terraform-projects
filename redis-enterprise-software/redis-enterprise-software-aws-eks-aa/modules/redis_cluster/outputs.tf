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

output "cluster_ready" {
  description = "Dependency marker — set only after REC reaches Running state"
  value       = null_resource.wait_for_cluster.id
}
