#==============================================================================
# DNS MODULE FOR REDIS ENTERPRISE EKS ACTIVE-ACTIVE
#==============================================================================
# Creates Route53 DNS records for Redis Enterprise API and database access.
# These records are required for Active-Active to work with RERC/REAADB.
#
# For EKS deployments, the records typically point to NLB DNS names or
# custom endpoints depending on the ingress configuration.
#==============================================================================

# Data source to get the hosted zone information
data "aws_route53_zone" "main" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
}

locals {
  hosted_zone_name = var.create_dns_records ? data.aws_route53_zone.main[0].name : ""
}

#==============================================================================
# API FQDN RECORD
#==============================================================================
# Creates a CNAME record for the Redis Enterprise API endpoint.
# Example: api-redis-cluster-us-west-2.example.com -> NLB DNS name

resource "aws_route53_record" "api_fqdn" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
  name    = var.api_fqdn
  type    = "CNAME"
  ttl     = 300
  records = [var.api_target]

  lifecycle {
    precondition {
      condition     = var.api_target != ""
      error_message = "api_target must not be empty. The nginx ingress NLB hostname may not have been assigned yet."
    }
  }
}

#==============================================================================
# DATABASE WILDCARD RECORD
#==============================================================================
# Creates a wildcard CNAME record for database access.
# Example: *.db.redis-cluster-us-west-2.example.com -> NLB DNS name
# This allows databases to be accessed as: mydb.db.redis-cluster-us-west-2.example.com

resource "aws_route53_record" "db_wildcard" {
  count   = var.create_dns_records ? 1 : 0
  zone_id = var.dns_hosted_zone_id
  name    = "*${var.db_fqdn_suffix}"
  type    = "CNAME"
  ttl     = 300
  records = [var.db_target]

  lifecycle {
    precondition {
      condition     = var.db_target != ""
      error_message = "db_target must not be empty. The nginx ingress NLB hostname may not have been assigned yet."
    }
  }
}
