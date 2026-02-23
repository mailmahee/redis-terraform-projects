#==============================================================================
# OUTPUTS - SINGLE REGION WRAPPER
#==============================================================================
# These outputs pass through the core module's outputs
#==============================================================================

output "cluster_name" {
  description = "Name of the Redis Enterprise cluster"
  value       = module.redis_enterprise_eks.cluster_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = module.redis_enterprise_eks.aws_region
}

output "eks_cluster_id" {
  description = "EKS cluster ID"
  value       = module.redis_enterprise_eks.eks_cluster_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.redis_enterprise_eks.eks_cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = module.redis_enterprise_eks.eks_cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.redis_enterprise_eks.eks_cluster_certificate_authority_data
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.redis_enterprise_eks.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.redis_enterprise_eks.private_subnet_ids
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = module.redis_enterprise_eks.private_route_table_ids
}

output "redis_namespace" {
  description = "Kubernetes namespace where Redis Enterprise is deployed"
  value       = module.redis_enterprise_eks.redis_namespace
}

output "redis_cluster_name" {
  description = "Name of the Redis Enterprise cluster (REC)"
  value       = module.redis_enterprise_eks.redis_cluster_name
}

output "redis_database_name" {
  description = "Name of the sample Redis database (if created)"
  value       = module.redis_enterprise_eks.redis_database_name
}

output "redis_database_port" {
  description = "Port of the sample Redis database"
  value       = module.redis_enterprise_eks.redis_database_port
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = module.redis_enterprise_eks.configure_kubectl
}

output "access_instructions" {
  description = "Instructions for accessing the Redis Enterprise cluster"
  value       = module.redis_enterprise_eks.access_instructions
}

output "next_steps" {
  description = "Recommended next steps after deployment"
  value       = module.redis_enterprise_eks.next_steps
}

output "bastion_public_ip" {
  description = "EC2 bastion public IP address"
  value       = module.redis_enterprise_eks.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to bastion instance"
  value       = module.redis_enterprise_eks.bastion_ssh_command
}

