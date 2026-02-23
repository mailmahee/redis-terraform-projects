#==============================================================================
# DNS MODULE VARIABLES
#==============================================================================

variable "create_dns_records" {
  description = "Whether to create DNS records in Route53"
  type        = bool
  default     = false
}

variable "dns_hosted_zone_id" {
  description = "Route53 hosted zone ID where DNS records will be created"
  type        = string
  default     = ""
}

variable "api_fqdn" {
  description = "Fully qualified domain name for the Redis Enterprise API endpoint (e.g., api-rec-region1-redis-enterprise.redisdemo.com)"
  type        = string
  default     = ""
}

variable "db_wildcard_fqdn" {
  description = "Wildcard FQDN for database access (e.g., *.db-rec-region1-redis-enterprise.redisdemo.com)"
  type        = string
  default     = ""
}

variable "db_fqdn_suffix" {
  description = "FQDN suffix for database access (e.g., -db-rec-region1-redis-enterprise.redisdemo.com)"
  type        = string
  default     = ""
}

variable "loadbalancer_dns_name" {
  description = "AWS LoadBalancer DNS name to point CNAME records to"
  type        = string
  default     = ""
}

variable "dns_ttl" {
  description = "TTL (in seconds) for DNS records"
  type        = number
  default     = 300
}

variable "validate_dns" {
  description = "Whether to validate DNS propagation after creating records"
  type        = bool
  default     = false
}

