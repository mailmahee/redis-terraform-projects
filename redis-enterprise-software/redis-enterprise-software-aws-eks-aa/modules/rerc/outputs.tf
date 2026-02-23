#==============================================================================
# RERC MODULE OUTPUTS
#==============================================================================

output "rerc_name" {
  description = "Name of the created RERC resource"
  value       = var.rerc_name
}

output "rerc_ready" {
  description = "Dependency marker indicating RERC is ready (Active status)"
  value       = null_resource.wait_for_rerc_active.id
}
