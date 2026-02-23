#==============================================================================
# REGION INFORMATION
#==============================================================================

output "region" {
  description = "AWS region where this cluster is deployed"
  value       = var.region
}

output "name_prefix" {
  description = "Full name prefix for this regional deployment"
  value       = local.name_prefix
}

#==============================================================================
# VPC OUTPUTS
#==============================================================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = var.vpc_cidr
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

output "public_route_table_id" {
  description = "Public route table ID (for VPC peering)"
  value       = module.vpc.public_route_table_id
}

output "private_route_table_ids" {
  description = "Private route table IDs (for VPC peering)"
  value       = module.vpc.private_route_table_ids
}

#==============================================================================
# EKS CLUSTER OUTPUTS
#==============================================================================

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = module.eks.cluster_version
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_cluster_certificate_authority_data" {
  description = "Certificate authority data for the EKS cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "eks_cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for the EKS cluster"
  value       = module.eks.cluster_oidc_issuer_url
}

output "eks_oidc_provider_arn" {
  description = "ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

#==============================================================================
# EKS NODE GROUP OUTPUTS
#==============================================================================

output "eks_node_group_id" {
  description = "EKS node group ID"
  value       = module.eks_node_group.node_group_id
}

output "eks_node_group_status" {
  description = "Status of the EKS node group"
  value       = module.eks_node_group.node_group_status
}

output "eks_node_security_group_id" {
  description = "Security group ID attached to EKS worker nodes"
  value       = module.eks_node_group.node_security_group_id
}

#==============================================================================
# REDIS ENTERPRISE OUTPUTS
#==============================================================================

output "redis_namespace" {
  description = "Kubernetes namespace where Redis Enterprise is deployed"
  value       = module.redis_operator.namespace
}

output "redis_operator_version" {
  description = "Version of the Redis Enterprise operator"
  value       = module.redis_operator.operator_version
}

output "redis_cluster_name" {
  description = "Name of the Redis Enterprise cluster (REC)"
  value       = module.redis_cluster.cluster_name
}

output "redis_cluster_nodes" {
  description = "Number of nodes in the Redis Enterprise cluster"
  value       = module.redis_cluster.node_count
}

output "rec_cluster_ready" {
  description = "Dependency marker — set only after REC reaches Running state"
  value       = module.redis_cluster.cluster_ready
}

output "redis_admin_credentials_secret_name" {
  description = "Name of the Kubernetes secret containing admin credentials"
  value       = module.redis_cluster.admin_credentials_secret_name
}

#==============================================================================
# STORAGE OUTPUTS
#==============================================================================

output "storage_class_name" {
  description = "Name of the storage class used for Redis Enterprise"
  value       = module.ebs_csi_driver.storage_class_name
}

output "ebs_csi_driver_version" {
  description = "Version of the EBS CSI driver addon"
  value       = module.ebs_csi_driver.ebs_csi_addon_version
}

#==============================================================================
# ACTIVE-ACTIVE SPECIFIC OUTPUTS
#==============================================================================

output "api_fqdn" {
  description = "API FQDN for this Redis Enterprise cluster (used in RERC)"
  value       = var.redis_api_fqdn_url
}

output "db_fqdn_suffix" {
  description = "Database FQDN suffix for this cluster"
  value       = var.redis_db_fqdn_suffix
}

#==============================================================================
# NGINX INGRESS OUTPUTS (for Active-Active DNS)
#==============================================================================

output "nginx_ingress_hostname" {
  description = "Nginx Ingress LoadBalancer hostname (for DNS CNAME records)"
  value       = var.enable_active_active && length(data.kubernetes_service.nginx_ingress) > 0 ? try(data.kubernetes_service.nginx_ingress[0].status[0].load_balancer[0].ingress[0].hostname, "") : ""

  precondition {
    condition     = !var.enable_active_active || (length(data.kubernetes_service.nginx_ingress) > 0 && try(data.kubernetes_service.nginx_ingress[0].status[0].load_balancer[0].ingress[0].hostname, "") != "")
    error_message = "Active-Active requires nginx ingress NLB hostname but it is empty. The NLB may have failed to provision. Check: kubectl get svc ingress-nginx-controller -n ingress-nginx"
  }
}

output "nginx_ingress_ready" {
  description = "Whether nginx ingress is ready"
  value       = var.enable_active_active ? (length(helm_release.nginx_ingress) > 0 ? helm_release.nginx_ingress[0].status : "not_deployed") : "not_required"
}

#==============================================================================
# KUBECTL CONFIGURATION
#==============================================================================

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${local.name_prefix}"
}
