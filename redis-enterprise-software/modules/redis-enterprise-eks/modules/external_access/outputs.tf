#==============================================================================
# External Access - Outputs
#==============================================================================

# NLB Outputs
output "ui_loadbalancer_dns" {
  description = "LoadBalancer DNS for Redis Enterprise UI (NLB mode)"
  value       = var.external_access_type == "nlb" && length(module.nlb_access) > 0 ? module.nlb_access[0].ui_loadbalancer_dns : null
}

output "database_loadbalancers" {
  description = "LoadBalancer DNS for each database (NLB mode)"
  value       = var.external_access_type == "nlb" && length(module.nlb_access) > 0 ? module.nlb_access[0].database_loadbalancers : {}
}

# NGINX Ingress Outputs
output "nginx_ingress_dns" {
  description = "NGINX Ingress LoadBalancer DNS (NGINX mode)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].ingress_loadbalancer_dns : null
}

output "nginx_ui_url_tls" {
  description = "NGINX Ingress URL for Redis Enterprise UI - TLS mode (NGINX mode)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].ui_url_tls : null
}

output "nginx_ui_url_non_tls" {
  description = "NGINX Ingress URL for Redis Enterprise UI - Non-TLS mode (NGINX mode)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].ui_url_non_tls : null
}

output "nginx_database_urls_tls" {
  description = "NGINX Ingress URLs for Redis databases - TLS mode (NGINX mode)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].database_urls_tls : {}
}

output "nginx_database_urls_non_tls" {
  description = "NGINX Ingress URLs for Redis databases - Non-TLS mode (NGINX mode)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].database_urls_non_tls : {}
}

output "nginx_mode" {
  description = "Current NGINX mode (TLS or non-TLS)"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].mode : null
}

output "nginx_dns_records_required" {
  description = "DNS records that need to be created for NGINX Ingress TLS mode"
  value       = var.external_access_type == "nginx-ingress" && length(module.nginx_ingress_access) > 0 ? module.nginx_ingress_access[0].dns_records_required : {}
}

# General output
output "external_access_enabled" {
  description = "Whether external access is enabled"
  value       = var.external_access_type != "none"
}

output "access_type" {
  description = "Type of external access configured"
  value       = var.external_access_type
}
