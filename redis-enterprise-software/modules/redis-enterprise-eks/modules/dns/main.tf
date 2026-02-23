#==============================================================================
# DNS MODULE FOR REDIS ENTERPRISE INGRESS
#==============================================================================
# Creates Route53 DNS records for Redis Enterprise cluster-to-cluster ingress
# Required for Active-Active (CRDB) databases
#==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#==============================================================================
# DATA SOURCES
#==============================================================================

# Get the hosted zone information
data "aws_route53_zone" "main" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
}

#==============================================================================
# DNS RECORDS
#==============================================================================

# API Endpoint CNAME Record
# Points api-rec-<name>-<namespace>.<domain> to the LoadBalancer DNS name
resource "aws_route53_record" "api" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
  name    = var.api_fqdn
  type    = "CNAME"
  ttl     = var.dns_ttl

  records = [var.loadbalancer_dns_name]
}

# Database Wildcard CNAME Record
# Points *-db-rec-<name>-<namespace>.<domain> to the LoadBalancer DNS name
resource "aws_route53_record" "database_wildcard" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
  name    = var.db_wildcard_fqdn
  type    = "CNAME"
  ttl     = var.dns_ttl

  records = [var.loadbalancer_dns_name]
}

#==============================================================================
# VALIDATION
#==============================================================================

# Validate that DNS records were created successfully
resource "null_resource" "validate_dns" {
  count = var.create_dns_records && var.validate_dns ? 1 : 0

  # Wait for DNS propagation
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for DNS propagation..."
      sleep 30
      
      echo "Validating API DNS record..."
      nslookup ${var.api_fqdn} || echo "Warning: DNS not yet propagated for ${var.api_fqdn}"
      
      echo "Validating Database DNS record..."
      nslookup test${var.db_fqdn_suffix} || echo "Warning: DNS not yet propagated for test${var.db_fqdn_suffix}"
    EOT
  }

  depends_on = [
    aws_route53_record.api,
    aws_route53_record.database_wildcard
  ]
}

