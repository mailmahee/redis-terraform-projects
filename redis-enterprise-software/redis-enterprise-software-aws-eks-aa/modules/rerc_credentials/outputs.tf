#==============================================================================
# RERC CREDENTIALS MODULE OUTPUTS
#==============================================================================

output "secret_name" {
  description = "Name of the created secret in the local cluster (redis-enterprise-<rerc_name>)"
  value       = kubernetes_secret.rerc_credentials.metadata[0].name
}

output "secret_namespace" {
  description = "Namespace of the created secret"
  value       = kubernetes_secret.rerc_credentials.metadata[0].namespace
}
