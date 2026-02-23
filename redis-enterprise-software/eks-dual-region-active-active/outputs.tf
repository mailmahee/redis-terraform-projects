#==============================================================================
# OUTPUTS - DUAL REGION
#==============================================================================

output "region1_info" {
  description = "Region 1 cluster information"
  value = {
    region                = var.region1
    vpc_id                = module.region1.vpc_id
    eks_cluster_name      = module.region1.eks_cluster_name
    eks_cluster_endpoint  = module.region1.eks_cluster_endpoint
    redis_namespace       = module.region1.redis_namespace
    redis_cluster_name    = module.region1.redis_cluster_name
  }
}

output "region2_info" {
  description = "Region 2 cluster information"
  value = {
    region                = var.region2
    vpc_id                = module.region2.vpc_id
    eks_cluster_name      = module.region2.eks_cluster_name
    eks_cluster_endpoint  = module.region2.eks_cluster_endpoint
    redis_namespace       = module.region2.redis_namespace
    redis_cluster_name    = module.region2.redis_cluster_name
  }
}

output "vpc_peering_connection_id" {
  description = "VPC peering connection ID"
  value       = aws_vpc_peering_connection.region1_to_region2.id
}

output "configure_kubectl_region1" {
  description = "Command to configure kubectl for region 1"
  value       = "aws eks update-kubeconfig --region ${var.region1} --name ${module.region1.eks_cluster_name}"
}

output "configure_kubectl_region2" {
  description = "Command to configure kubectl for region 2"
  value       = "aws eks update-kubeconfig --region ${var.region2} --name ${module.region2.eks_cluster_name}"
}

output "verification_commands" {
  description = "Commands to verify the deployment"
  value       = <<-EOT
    # Configure kubectl for Region 1
    aws eks update-kubeconfig --region ${var.region1} --name ${module.region1.eks_cluster_name}
    
    # Check Redis Enterprise Cluster in Region 1
    kubectl get rec -n ${module.region1.redis_namespace}
    kubectl get pods -n ${module.region1.redis_namespace}
    
    # Configure kubectl for Region 2
    aws eks update-kubeconfig --region ${var.region2} --name ${module.region2.eks_cluster_name}
    
    # Check Redis Enterprise Cluster in Region 2
    kubectl get rec -n ${module.region2.redis_namespace}
    kubectl get pods -n ${module.region2.redis_namespace}
    
    # Test VPC peering (from region1 node to region2 VPC)
    # This requires SSH access to nodes or running a test pod
  EOT
}

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ✅ Deployment Complete!
    
    Both regions are deployed with independent Redis Enterprise clusters.
    VPC peering is configured between the regions.
    
    Next steps:
    1. Verify both RECs are Running (see verification_commands output)
    2. Test connectivity to databases in both regions
    3. (Optional) Configure Active-Active replication between regions
    
    Note: These are INDEPENDENT clusters. No replication is configured yet.
  EOT
}

