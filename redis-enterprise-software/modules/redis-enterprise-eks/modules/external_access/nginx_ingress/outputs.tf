#==============================================================================
# NGINX INGRESS EXTERNAL ACCESS - OUTPUTS
#==============================================================================

# Get the LoadBalancer DNS name from the NGINX Ingress Controller service
data "kubernetes_service_v1" "nginx_ingress_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.nginx_ingress]
}

output "ingress_loadbalancer_dns" {
  description = "AWS NLB DNS name for NGINX Ingress Controller"
  value       = try(data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "ui_url_tls" {
  description = "Redis Enterprise UI URL via NGINX Ingress (TLS mode)"
  value       = var.expose_ui && var.enable_tls ? "https://ui-${var.ingress_domain}:443" : "not-configured"
}

output "ui_url_non_tls" {
  description = "Redis Enterprise UI URL via NGINX Ingress (non-TLS mode)"
  value       = var.expose_ui && !var.enable_tls ? "http://ui-${var.ingress_domain}" : "not-configured"
}

output "database_urls_tls" {
  description = "Redis database connection URLs via NGINX Ingress (TLS mode)"
  value = var.expose_databases && var.enable_tls ? {
    for db_name, db_config in var.redis_db_services :
    db_name => "rediss://${db_name}-${var.ingress_domain}:443"
  } : {}
}

output "database_urls_non_tls" {
  description = "Redis database connection URLs via NGINX Ingress (non-TLS mode)"
  value = var.expose_databases && !var.enable_tls ? {
    for db_name, db_config in var.redis_db_services :
    db_name => "redis://${data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname}:${db_config.port}"
  } : {}
}

output "mode" {
  description = "Current external access mode (TLS or non-TLS)"
  value       = var.enable_tls ? "TLS (Production)" : "Non-TLS (Testing)"
}

output "dns_records_required" {
  description = "DNS records that need to be created (for TLS mode)"
  value = var.enable_tls ? merge(
    var.expose_ui ? {
      "ui" = {
        hostname = "ui-${var.ingress_domain}"
        target   = try(data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname, "pending")
        type     = "CNAME"
      }
    } : {},
    var.expose_databases ? {
      for db_name, db_config in var.redis_db_services :
      db_name => {
        hostname = "${db_name}-${var.ingress_domain}"
        target   = try(data.kubernetes_service_v1.nginx_ingress_controller.status[0].load_balancer[0].ingress[0].hostname, "pending")
        type     = "CNAME"
      }
    } : {}
  ) : {}
}
