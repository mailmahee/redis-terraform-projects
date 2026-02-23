#==============================================================================
# DNS MODULE VARIABLES
#==============================================================================

variable "create_dns_records" {
  description = "Whether to create Route53 DNS records"
  type        = bool
  default     = true
}

variable "dns_hosted_zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "api_fqdn" {
  description = "FQDN for the Redis Enterprise API (e.g., api-redis-cluster-us-west-2.example.com)"
  type        = string
}

variable "api_target" {
  description = "Target for the API CNAME record (e.g., NLB DNS name)"
  type        = string
}

variable "db_fqdn_suffix" {
  description = "FQDN suffix for database access (e.g., db.redis-cluster-us-west-2.example.com)"
  type        = string
}

variable "db_target" {
  description = "Target for the database CNAME record (e.g., NLB DNS name)"
  type        = string
}
