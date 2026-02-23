#==============================================================================
# LOCALS FOR COMPLEX OUTPUT VALUES
#==============================================================================

locals {
  verification_commands_text = <<-EOT
    # Switch to Region 1
    aws eks update-kubeconfig --region ${local.region_list[0]} --name ${module.redis_cluster_region1.eks_cluster_name}

    # Check REC status
    kubectl get rec -n ${var.redis_enterprise_namespace}

    # Check RERC status (should show Active)
    kubectl get rerc -n ${var.redis_enterprise_namespace}

    # Check REAADB status (should show Active on all participating clusters)
    kubectl get reaadb -n ${var.redis_enterprise_namespace}

    # Describe REAADB for detailed status
    kubectl describe reaadb ${var.aa_database_name} -n ${var.redis_enterprise_namespace}

    # Switch to Region 2 and verify
    aws eks update-kubeconfig --region ${local.region_list[1]} --name ${module.redis_cluster_region2[0].eks_cluster_name}
    kubectl get rec,rerc,reaadb -n ${var.redis_enterprise_namespace}
  EOT
}

#==============================================================================
# DEPLOYMENT INFORMATION
#==============================================================================

output "deployment_type" {
  description = "Type of deployment (single-region or multi-region Active-Active)"
  value       = length(local.region_list) > 1 ? "multi-region-active-active" : "single-region"
}

output "regions" {
  description = "List of regions where clusters are deployed"
  value       = local.region_list
}

#==============================================================================
# REGION 1 CLUSTER OUTPUTS
#==============================================================================

output "region1_cluster_info" {
  description = "Region 1 Redis Enterprise cluster information"
  value = {
    region               = local.region_list[0]
    eks_cluster_name     = module.redis_cluster_region1.eks_cluster_name
    eks_cluster_endpoint = module.redis_cluster_region1.eks_cluster_endpoint
    vpc_id               = module.redis_cluster_region1.vpc_id
    redis_namespace      = module.redis_cluster_region1.redis_namespace
    redis_cluster_name   = module.redis_cluster_region1.redis_cluster_name
    api_fqdn             = module.redis_cluster_region1.api_fqdn
    db_fqdn_suffix       = module.redis_cluster_region1.db_fqdn_suffix
  }
}

output "region1_configure_kubectl" {
  description = "Command to configure kubectl for region 1 cluster"
  value       = module.redis_cluster_region1.configure_kubectl
}

#==============================================================================
# REGION 2 CLUSTER OUTPUTS (if multi-region)
#==============================================================================

output "region2_cluster_info" {
  description = "Region 2 Redis Enterprise cluster information (if multi-region)"
  value = length(local.region_list) > 1 ? {
    region               = local.region_list[1]
    eks_cluster_name     = module.redis_cluster_region2[0].eks_cluster_name
    eks_cluster_endpoint = module.redis_cluster_region2[0].eks_cluster_endpoint
    vpc_id               = module.redis_cluster_region2[0].vpc_id
    redis_namespace      = module.redis_cluster_region2[0].redis_namespace
    redis_cluster_name   = module.redis_cluster_region2[0].redis_cluster_name
    api_fqdn             = module.redis_cluster_region2[0].api_fqdn
    db_fqdn_suffix       = module.redis_cluster_region2[0].db_fqdn_suffix
  } : null
}

output "region2_configure_kubectl" {
  description = "Command to configure kubectl for region 2 cluster"
  value       = length(local.region_list) > 1 ? module.redis_cluster_region2[0].configure_kubectl : null
}

#==============================================================================
# VPC PEERING OUTPUTS
#==============================================================================

output "vpc_peering_status" {
  description = "Status of VPC peering connections"
  value       = length(local.region_list) > 1 && length(module.vpc_peering_mesh) > 0 ? module.vpc_peering_mesh[0].peering_connection_status : null
}

output "vpc_peering_pairs" {
  description = "List of VPC peering pairs"
  value       = length(local.region_list) > 1 && length(module.vpc_peering_mesh) > 0 ? module.vpc_peering_mesh[0].region_pairs : null
}

#==============================================================================
# ACTIVE-ACTIVE DATABASE OUTPUTS
#==============================================================================

output "aa_database_name" {
  description = "Name of the Active-Active database"
  value       = var.create_aa_database && length(local.region_list) > 1 ? module.aa_database[0].database_name : null
}

output "aa_database_endpoints" {
  description = "Active-Active database endpoints in each region"
  value = var.create_aa_database && length(local.region_list) > 1 ? {
    (local.region_list[0]) = "${var.aa_database_name}.db.${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
    (local.region_list[1]) = "${var.aa_database_name}.db.${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  } : null
}

#==============================================================================
# ACCESS INSTRUCTIONS
#==============================================================================

output "access_instructions" {
  description = "Instructions for accessing the Redis Enterprise clusters"
  value = <<-EOT

    ╔════════════════════════════════════════════════════════════════════════════╗
    ║        REDIS ENTERPRISE ON EKS - ACTIVE-ACTIVE ACCESS INSTRUCTIONS         ║
    ╚════════════════════════════════════════════════════════════════════════════╝

    DEPLOYMENT TYPE: ${length(local.region_list) > 1 ? "Multi-Region Active-Active" : "Single Region"}
    REGIONS: ${join(", ", local.region_list)}

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    REGION 1: ${local.region_list[0]}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    1. CONFIGURE KUBECTL
       aws eks update-kubeconfig --region ${local.region_list[0]} --name ${module.redis_cluster_region1.eks_cluster_name}

    2. VERIFY CLUSTER STATUS
       kubectl get rec -n ${var.redis_enterprise_namespace}
       kubectl get pods -n ${var.redis_enterprise_namespace}
       ${length(local.region_list) > 1 ? "kubectl get rerc -n ${var.redis_enterprise_namespace}" : ""}
       ${var.create_aa_database && length(local.region_list) > 1 ? "kubectl get reaadb -n ${var.redis_enterprise_namespace}" : ""}

    3. ACCESS REDIS ENTERPRISE UI
       kubectl port-forward -n ${var.redis_enterprise_namespace} svc/${var.cluster_name}-ui 8443:8443

       Then access: https://localhost:8443
       Username: ${var.redis_cluster_username}
       Password: [your configured password]

    ${length(local.region_list) > 1 ? <<-REGION2
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    REGION 2: ${local.region_list[1]}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    1. CONFIGURE KUBECTL
       aws eks update-kubeconfig --region ${local.region_list[1]} --name ${module.redis_cluster_region2[0].eks_cluster_name}

    2. VERIFY CLUSTER STATUS
       kubectl get rec -n ${var.redis_enterprise_namespace}
       kubectl get rerc -n ${var.redis_enterprise_namespace}
       ${var.create_aa_database ? "kubectl get reaadb -n ${var.redis_enterprise_namespace}" : ""}
    REGION2
  : ""}

    ${var.create_aa_database && length(local.region_list) > 1 ? <<-AADB
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    ACTIVE-ACTIVE DATABASE: ${var.aa_database_name}
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    Database is replicated across both regions. Connect to either endpoint:

    Region 1 (${local.region_list[0]}):
       ${var.aa_database_name}.db.${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}

    Region 2 (${local.region_list[1]}):
       ${var.aa_database_name}.db.${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}

    Test connectivity from a pod:
       kubectl run redis-test --image=redis:latest -n ${var.redis_enterprise_namespace} --rm -it -- bash
       redis-cli -h ${var.aa_database_name}.db.${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name} PING
    AADB
: ""}

    ════════════════════════════════════════════════════════════════════════════
  EOT
}

#==============================================================================
# VERIFICATION COMMANDS
#==============================================================================

output "verification_commands" {
  description = "Commands to verify the Active-Active deployment"
  value       = length(local.region_list) > 1 ? local.verification_commands_text : null
}
