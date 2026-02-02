#==============================================================================
# NLB External Access - Outputs
#==============================================================================

output "ui_loadbalancer_dns" {
  description = "AWS NLB DNS name for Redis Enterprise UI"
  value       = var.expose_ui && length(kubernetes_service_v1.redis_ui_external) > 0 ? try(kubernetes_service_v1.redis_ui_external[0].status[0].load_balancer[0].ingress[0].hostname, null) : null
}

output "ui_loadbalancer_ip" {
  description = "AWS NLB IP address for Redis Enterprise UI (if available)"
  value       = var.expose_ui && length(kubernetes_service_v1.redis_ui_external) > 0 ? try(kubernetes_service_v1.redis_ui_external[0].status[0].load_balancer[0].ingress[0].ip, null) : null
}

output "database_loadbalancers" {
  description = "Map of database names to their NLB DNS names"
  value = {
    for db_name, svc in kubernetes_service_v1.redis_db_external :
    db_name => try(svc.status[0].load_balancer[0].ingress[0].hostname, null)
  }
}

output "database_loadbalancer_ips" {
  description = "Map of database names to their NLB IP addresses (if available)"
  value = {
    for db_name, svc in kubernetes_service_v1.redis_db_external :
    db_name => try(svc.status[0].load_balancer[0].ingress[0].ip, null)
  }
}

output "ui_service_name" {
  description = "Name of the external UI service"
  value       = var.expose_ui && length(kubernetes_service_v1.redis_ui_external) > 0 ? kubernetes_service_v1.redis_ui_external[0].metadata[0].name : null
}

output "database_service_names" {
  description = "Map of database names to their external service names"
  value = {
    for db_name, svc in kubernetes_service_v1.redis_db_external :
    db_name => svc.metadata[0].name
  }
}
