output "namespace" {
  description = "Kubernetes namespace where Redis Enterprise operator is installed"
  value       = kubernetes_namespace.redis_enterprise.metadata[0].name
}

output "operator_version" {
  description = "Version of the deployed Redis Enterprise operator bundle"
  value       = var.operator_version
}

output "operator_ready" {
  description = "Indicates that the operator is ready for use"
  value       = time_sleep.wait_for_operator.id
}
