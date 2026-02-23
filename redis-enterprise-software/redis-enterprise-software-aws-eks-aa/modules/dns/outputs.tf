#==============================================================================
# DNS MODULE OUTPUTS
#==============================================================================

output "api_fqdn" {
  description = "Full API FQDN"
  value       = var.create_dns_records ? aws_route53_record.api_fqdn[0].fqdn : var.api_fqdn
}

output "db_fqdn_suffix" {
  description = "Database FQDN suffix"
  value       = var.db_fqdn_suffix
}

output "hosted_zone_name" {
  description = "Name of the hosted zone"
  value       = local.hosted_zone_name
}
