#==============================================================================
# REAADB MODULE OUTPUTS
#==============================================================================

output "database_name" {
  description = "Name of the created Active-Active database"
  value       = var.create_database ? var.database_name : null
}

output "database_ready" {
  description = "Dependency marker indicating REAADB is ready"
  value       = var.create_database ? null_resource.wait_for_reaadb_active[0].id : null
}
