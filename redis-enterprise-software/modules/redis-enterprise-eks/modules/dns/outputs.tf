#==============================================================================
# DNS MODULE OUTPUTS
#==============================================================================

output "api_record_fqdn" {
  description = "The FQDN of the created API DNS record"
  value       = var.create_dns_records ? var.api_fqdn : ""
}

output "db_wildcard_record_fqdn" {
  description = "The wildcard FQDN of the created database DNS record"
  value       = var.create_dns_records ? var.db_wildcard_fqdn : ""
}

output "dns_records_created" {
  description = "Whether DNS records were created"
  value       = var.create_dns_records
}

output "api_record_id" {
  description = "The Route53 record ID for the API endpoint"
  value       = var.create_dns_records ? aws_route53_record.api[0].id : ""
}

output "db_wildcard_record_id" {
  description = "The Route53 record ID for the database wildcard"
  value       = var.create_dns_records ? aws_route53_record.database_wildcard[0].id : ""
}

output "hosted_zone_name" {
  description = "The name of the Route53 hosted zone"
  value       = var.create_dns_records ? data.aws_route53_zone.main[0].name : ""
}

