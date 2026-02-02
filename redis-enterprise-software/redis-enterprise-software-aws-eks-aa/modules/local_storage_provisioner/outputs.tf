output "provisioner_deployed" {
  description = "Whether the local storage provisioner was deployed"
  value       = var.enable_provisioner
}

output "provisioner_ready" {
  description = "Provisioner deployment object for dependency chaining"
  value       = var.enable_provisioner ? time_sleep.wait_for_nvme_discovery[0] : null
}
