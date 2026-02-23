#==============================================================================
# REDIS ENTERPRISE SOFTWARE ON AWS EKS - ACTIVE-ACTIVE (MULTI-REGION)
#==============================================================================
# This configuration deploys Redis Enterprise Software clusters across multiple
# AWS regions with Active-Active (CRDB) database replication using Kubernetes
# CRDs (RERC and REAADB).
#
# Architecture:
# - EKS cluster with Redis Enterprise operator in each region
# - VPC peering mesh for cross-region communication
# - RERC (RedisEnterpriseRemoteCluster) for cluster discovery
# - REAADB (RedisEnterpriseActiveActiveDatabase) for Active-Active databases
#==============================================================================

# Get hosted zone information for DNS
data "aws_route53_zone" "main" {
  zone_id = var.dns_hosted_zone_id
}

#==============================================================================
# LOCAL VARIABLES
#==============================================================================

locals {
  name_prefix = "${var.user_prefix}-${var.cluster_name}"
  region_list = keys(var.regions)

  # Generate peer region CIDRs for each region (all other regions' CIDRs)
  peer_region_cidrs = {
    for region, config in var.regions : region => [
      for peer_region, peer_config in var.regions :
      peer_config.vpc_cidr
      if peer_region != region
    ]
  }

  # Shared configuration for all region modules
  region_module_shared_config = {
    # Global configuration
    user_prefix  = var.user_prefix
    cluster_name = var.cluster_name
    owner        = var.owner
    project      = var.project
    environment  = var.environment
    tags         = var.tags

    # EKS configuration
    kubernetes_version              = var.kubernetes_version
    cluster_endpoint_public_access  = var.cluster_endpoint_public_access
    cluster_endpoint_private_access = var.cluster_endpoint_private_access
    node_instance_types             = var.node_instance_types
    node_desired_size               = var.node_desired_size
    node_min_size                   = var.node_min_size
    node_max_size                   = var.node_max_size
    node_disk_size                  = var.node_disk_size

    # Redis Enterprise configuration
    redis_enterprise_namespace   = var.redis_enterprise_namespace
    redis_operator_version       = var.redis_operator_version
    redis_cluster_nodes          = var.redis_cluster_nodes
    redis_cluster_username       = var.redis_cluster_username
    redis_cluster_password       = var.redis_cluster_password
    redis_cluster_memory         = var.redis_cluster_memory
    redis_cluster_storage_size   = var.redis_cluster_storage_size
    redis_cluster_storage_class  = var.redis_cluster_storage_class
    redis_enterprise_version_tag = var.redis_enterprise_version_tag

    # Redis Flex configuration (incompatible with AA)
    enable_redis_flex          = var.enable_redis_flex
    redis_flex_storage_class   = var.redis_flex_storage_class
    redis_flex_flash_disk_size = var.redis_flex_flash_disk_size
    redis_flex_storage_driver  = var.redis_flex_storage_driver

    # UI/Service configuration
    redis_ui_service_type       = var.redis_ui_service_type
    ui_internal_lb_enabled      = var.ui_internal_lb_enabled
    ui_service_annotations      = var.ui_service_annotations
    redis_database_service_type = var.redis_database_service_type
    redis_license_secret_name   = var.redis_license_secret_name

    # Ingress configuration (required for AA)
    redis_enable_ingress      = true # Always enabled for AA
    redis_ingress_method      = var.redis_ingress_method
    redis_ingress_annotations = var.redis_ingress_annotations

    # Active-Active
    enable_active_active = length(local.region_list) > 1
  }

  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ClusterName = var.cluster_name
    }
  )
}

#==============================================================================
# VALIDATION: Active-Active requires at least 2 regions
#==============================================================================

resource "null_resource" "validate_aa_config" {
  count = var.create_aa_database && length(local.region_list) < 2 ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.create_aa_database || length(local.region_list) >= 2
      error_message = "Active-Active database requires at least 2 regions to be configured."
    }
  }
}

resource "null_resource" "validate_flex_aa_incompatibility" {
  count = var.enable_redis_flex && length(local.region_list) > 1 ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.enable_redis_flex || length(local.region_list) <= 1
      error_message = "Redis Flex (Auto Tiering) is incompatible with Active-Active. Disable enable_redis_flex for multi-region deployments."
    }
  }
}

#==============================================================================
# REDIS ENTERPRISE CLUSTERS (Multi-Region)
#==============================================================================
# Terraform doesn't support dynamic provider assignment in for_each loops,
# so we maintain separate module blocks per region.
#==============================================================================

module "redis_cluster_region1" {
  source = "./modules/single_region_eks"

  providers = {
    aws        = aws.region1
    kubernetes = kubernetes.region1
    helm       = helm.region1
    kubectl    = kubectl.region1
  }

  # Region-specific configuration
  region               = local.region_list[0]
  vpc_cidr             = var.regions[local.region_list[0]].vpc_cidr
  public_subnet_cidrs  = var.regions[local.region_list[0]].public_subnet_cidrs
  private_subnet_cidrs = var.regions[local.region_list[0]].private_subnet_cidrs
  availability_zones   = var.regions[local.region_list[0]].availability_zones
  peer_region_cidrs    = local.peer_region_cidrs[local.region_list[0]]

  # API/DB FQDNs for this region
  redis_api_fqdn_url   = "api-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  redis_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"

  # Shared configuration
  user_prefix                     = local.region_module_shared_config.user_prefix
  cluster_name                    = local.region_module_shared_config.cluster_name
  owner                           = local.region_module_shared_config.owner
  project                         = local.region_module_shared_config.project
  environment                     = local.region_module_shared_config.environment
  tags                            = local.region_module_shared_config.tags
  kubernetes_version              = local.region_module_shared_config.kubernetes_version
  cluster_endpoint_public_access  = local.region_module_shared_config.cluster_endpoint_public_access
  cluster_endpoint_private_access = local.region_module_shared_config.cluster_endpoint_private_access
  node_instance_types             = local.region_module_shared_config.node_instance_types
  node_desired_size               = local.region_module_shared_config.node_desired_size
  node_min_size                   = local.region_module_shared_config.node_min_size
  node_max_size                   = local.region_module_shared_config.node_max_size
  node_disk_size                  = local.region_module_shared_config.node_disk_size
  redis_enterprise_namespace      = local.region_module_shared_config.redis_enterprise_namespace
  redis_operator_version          = local.region_module_shared_config.redis_operator_version
  redis_cluster_nodes             = local.region_module_shared_config.redis_cluster_nodes
  redis_cluster_username          = local.region_module_shared_config.redis_cluster_username
  redis_cluster_password          = local.region_module_shared_config.redis_cluster_password
  redis_cluster_memory            = local.region_module_shared_config.redis_cluster_memory
  redis_cluster_storage_size      = local.region_module_shared_config.redis_cluster_storage_size
  redis_cluster_storage_class     = local.region_module_shared_config.redis_cluster_storage_class
  redis_enterprise_version_tag    = local.region_module_shared_config.redis_enterprise_version_tag
  enable_redis_flex               = local.region_module_shared_config.enable_redis_flex
  redis_flex_storage_class        = local.region_module_shared_config.redis_flex_storage_class
  redis_flex_flash_disk_size      = local.region_module_shared_config.redis_flex_flash_disk_size
  redis_flex_storage_driver       = local.region_module_shared_config.redis_flex_storage_driver
  redis_ui_service_type           = local.region_module_shared_config.redis_ui_service_type
  ui_internal_lb_enabled          = local.region_module_shared_config.ui_internal_lb_enabled
  ui_service_annotations          = local.region_module_shared_config.ui_service_annotations
  redis_database_service_type     = local.region_module_shared_config.redis_database_service_type
  redis_license_secret_name       = local.region_module_shared_config.redis_license_secret_name
  redis_enable_ingress            = local.region_module_shared_config.redis_enable_ingress
  redis_ingress_method            = local.region_module_shared_config.redis_ingress_method
  redis_ingress_annotations       = local.region_module_shared_config.redis_ingress_annotations
  enable_active_active            = local.region_module_shared_config.enable_active_active
}

module "redis_cluster_region2" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/single_region_eks"

  providers = {
    aws        = aws.region2
    kubernetes = kubernetes.region2
    helm       = helm.region2
    kubectl    = kubectl.region2
  }

  # Region-specific configuration
  region               = local.region_list[1]
  vpc_cidr             = var.regions[local.region_list[1]].vpc_cidr
  public_subnet_cidrs  = var.regions[local.region_list[1]].public_subnet_cidrs
  private_subnet_cidrs = var.regions[local.region_list[1]].private_subnet_cidrs
  availability_zones   = var.regions[local.region_list[1]].availability_zones
  peer_region_cidrs    = local.peer_region_cidrs[local.region_list[1]]

  # API/DB FQDNs for this region
  redis_api_fqdn_url   = "api-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  redis_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"

  # Shared configuration
  user_prefix                     = local.region_module_shared_config.user_prefix
  cluster_name                    = local.region_module_shared_config.cluster_name
  owner                           = local.region_module_shared_config.owner
  project                         = local.region_module_shared_config.project
  environment                     = local.region_module_shared_config.environment
  tags                            = local.region_module_shared_config.tags
  kubernetes_version              = local.region_module_shared_config.kubernetes_version
  cluster_endpoint_public_access  = local.region_module_shared_config.cluster_endpoint_public_access
  cluster_endpoint_private_access = local.region_module_shared_config.cluster_endpoint_private_access
  node_instance_types             = local.region_module_shared_config.node_instance_types
  node_desired_size               = local.region_module_shared_config.node_desired_size
  node_min_size                   = local.region_module_shared_config.node_min_size
  node_max_size                   = local.region_module_shared_config.node_max_size
  node_disk_size                  = local.region_module_shared_config.node_disk_size
  redis_enterprise_namespace      = local.region_module_shared_config.redis_enterprise_namespace
  redis_operator_version          = local.region_module_shared_config.redis_operator_version
  redis_cluster_nodes             = local.region_module_shared_config.redis_cluster_nodes
  redis_cluster_username          = local.region_module_shared_config.redis_cluster_username
  redis_cluster_password          = local.region_module_shared_config.redis_cluster_password
  redis_cluster_memory            = local.region_module_shared_config.redis_cluster_memory
  redis_cluster_storage_size      = local.region_module_shared_config.redis_cluster_storage_size
  redis_cluster_storage_class     = local.region_module_shared_config.redis_cluster_storage_class
  redis_enterprise_version_tag    = local.region_module_shared_config.redis_enterprise_version_tag
  enable_redis_flex               = local.region_module_shared_config.enable_redis_flex
  redis_flex_storage_class        = local.region_module_shared_config.redis_flex_storage_class
  redis_flex_flash_disk_size      = local.region_module_shared_config.redis_flex_flash_disk_size
  redis_flex_storage_driver       = local.region_module_shared_config.redis_flex_storage_driver
  redis_ui_service_type           = local.region_module_shared_config.redis_ui_service_type
  ui_internal_lb_enabled          = local.region_module_shared_config.ui_internal_lb_enabled
  ui_service_annotations          = local.region_module_shared_config.ui_service_annotations
  redis_database_service_type     = local.region_module_shared_config.redis_database_service_type
  redis_license_secret_name       = local.region_module_shared_config.redis_license_secret_name
  redis_enable_ingress            = local.region_module_shared_config.redis_enable_ingress
  redis_ingress_method            = local.region_module_shared_config.redis_ingress_method
  redis_ingress_annotations       = local.region_module_shared_config.redis_ingress_annotations
  enable_active_active            = local.region_module_shared_config.enable_active_active
}

#==============================================================================
# VPC PEERING MESH
#==============================================================================
# Creates VPC peering connections between all regions for cross-region
# Redis Enterprise communication.
#==============================================================================

module "vpc_peering_mesh" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/vpc_peering_mesh"

  providers = {
    aws.region1 = aws.region1
    aws.region2 = aws.region2
  }

  name_prefix = local.name_prefix

  # Pass VPC information from all clusters
  region_configs = merge(
    {
      (local.region_list[0]) = {
        vpc_id                  = module.redis_cluster_region1.vpc_id
        vpc_cidr                = var.regions[local.region_list[0]].vpc_cidr
        public_route_table_id   = module.redis_cluster_region1.public_route_table_id
        private_route_table_ids = module.redis_cluster_region1.private_route_table_ids
      }
    },
    length(local.region_list) > 1 ? {
      (local.region_list[1]) = {
        vpc_id                  = module.redis_cluster_region2[0].vpc_id
        vpc_cidr                = var.regions[local.region_list[1]].vpc_cidr
        public_route_table_id   = module.redis_cluster_region2[0].public_route_table_id
        private_route_table_ids = module.redis_cluster_region2[0].private_route_table_ids
      }
    } : {}
  )

  # Static count for private route tables (matches subnet configuration)
  private_subnet_count = length(var.regions[local.region_list[0]].private_subnet_cidrs)

  owner   = var.owner
  project = var.project
  tags    = local.tags

  depends_on = [module.redis_cluster_region1, module.redis_cluster_region2]
}

#==============================================================================
# DNS RECORDS (Required for Active-Active)
#==============================================================================
# Creates Route53 DNS records pointing to nginx ingress LoadBalancer.
# Per Redis docs, DNS must point to the ingress controller, not EKS endpoint.
# https://redis.io/docs/latest/operate/kubernetes/networking/ingressorroutespec/
#==============================================================================

module "dns_region1" {
  count  = var.create_dns_records ? 1 : 0
  source = "./modules/dns"

  providers = {
    aws = aws.region1
  }

  create_dns_records = var.create_dns_records
  dns_hosted_zone_id = var.dns_hosted_zone_id

  api_fqdn = "api-${local.name_prefix}-${local.region_list[0]}"
  # DNS must point to nginx ingress LoadBalancer for Active-Active to work
  api_target     = module.redis_cluster_region1.nginx_ingress_hostname
  db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  db_target      = module.redis_cluster_region1.nginx_ingress_hostname

  depends_on = [module.redis_cluster_region1]
}

module "dns_region2" {
  count  = var.create_dns_records && length(local.region_list) > 1 ? 1 : 0
  source = "./modules/dns"

  providers = {
    aws = aws.region2
  }

  create_dns_records = var.create_dns_records
  dns_hosted_zone_id = var.dns_hosted_zone_id

  api_fqdn = "api-${local.name_prefix}-${local.region_list[1]}"
  # DNS must point to nginx ingress LoadBalancer for Active-Active to work
  api_target     = module.redis_cluster_region2[0].nginx_ingress_hostname
  db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  db_target      = module.redis_cluster_region2[0].nginx_ingress_hostname

  depends_on = [module.redis_cluster_region2]
}

#==============================================================================
# DNS RESOLUTION VERIFICATION
#==============================================================================
# After creating Route53 records, verify the FQDNs actually resolve before
# proceeding. DNS propagation can take time, and the CRDB coordinator needs
# working DNS to reach remote clusters during provisioning.
#==============================================================================

resource "null_resource" "verify_dns_resolution" {
  count = var.create_dns_records && length(local.region_list) > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      echo "Verifying DNS resolution for Active-Active FQDNs..."
      FQDNS=(
        "api-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
        "api-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
      )
      MAX_ATTEMPTS=30
      for FQDN in "$${FQDNS[@]}"; do
        echo "Checking resolution of $FQDN..."
        ATTEMPT=0
        while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
          RESULT=$(nslookup "$FQDN" 2>/dev/null | grep -i "canonical name\|address" | head -1)
          if [ -n "$RESULT" ]; then
            echo "  Resolved: $RESULT"
            break
          fi
          ATTEMPT=$((ATTEMPT+1))
          echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS: not yet resolving, waiting 10s..."
          sleep 10
        done
        if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
          echo "ERROR: $FQDN did not resolve within 5 minutes."
          echo "Check Route53 records: aws route53 list-resource-record-sets --hosted-zone-id ${var.dns_hosted_zone_id}"
          exit 1
        fi
      done
      echo "All DNS FQDNs resolved successfully."
    EOF
  }

  depends_on = [module.dns_region1, module.dns_region2]
}

#==============================================================================
# RERC CREDENTIALS EXCHANGE
#==============================================================================
# Per Redis docs: https://redis.io/docs/latest/operate/kubernetes/active-active/prepare-clusters/
# Each cluster needs:
# 1. Its OWN credentials secret (for local RERC)
# 2. REMOTE cluster credentials (for remote RERCs)
# Secret naming: redis-enterprise-<rerc-name>
#==============================================================================

# Region1: Create secret for LOCAL RERC (self-credentials)
module "rerc_credentials_region1_local" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc_credentials"

  providers = {
    kubernetes.local  = kubernetes.region1
    kubernetes.remote = kubernetes.region1 # Same region - local credentials
  }

  local_namespace  = var.redis_enterprise_namespace
  remote_namespace = var.redis_enterprise_namespace
  remote_rec_name  = var.cluster_name
  rerc_name        = "rerc-${local.region_list[0]}" # Local RERC for region1

  depends_on = [
    module.redis_cluster_region1,
    module.vpc_peering_mesh,
    null_resource.verify_dns_resolution
  ]
}

# Region1: Create secret for REMOTE RERC (region2 credentials)
module "rerc_credentials_region1_remote" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc_credentials"

  providers = {
    kubernetes.local  = kubernetes.region1
    kubernetes.remote = kubernetes.region2
  }

  local_namespace  = var.redis_enterprise_namespace
  remote_namespace = var.redis_enterprise_namespace
  remote_rec_name  = var.cluster_name
  rerc_name        = "rerc-${local.region_list[1]}" # Remote RERC for region2

  depends_on = [
    module.redis_cluster_region1,
    module.redis_cluster_region2,
    module.vpc_peering_mesh,
    null_resource.verify_dns_resolution
  ]
}

# Region2: Create secret for LOCAL RERC (self-credentials)
module "rerc_credentials_region2_local" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc_credentials"

  providers = {
    kubernetes.local  = kubernetes.region2
    kubernetes.remote = kubernetes.region2 # Same region - local credentials
  }

  local_namespace  = var.redis_enterprise_namespace
  remote_namespace = var.redis_enterprise_namespace
  remote_rec_name  = var.cluster_name
  rerc_name        = "rerc-${local.region_list[1]}" # Local RERC for region2

  depends_on = [
    module.redis_cluster_region2,
    module.vpc_peering_mesh,
    null_resource.verify_dns_resolution
  ]
}

# Region2: Create secret for REMOTE RERC (region1 credentials)
module "rerc_credentials_region2_remote" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc_credentials"

  providers = {
    kubernetes.local  = kubernetes.region2
    kubernetes.remote = kubernetes.region1
  }

  local_namespace  = var.redis_enterprise_namespace
  remote_namespace = var.redis_enterprise_namespace
  remote_rec_name  = var.cluster_name
  rerc_name        = "rerc-${local.region_list[0]}" # Remote RERC for region1

  depends_on = [
    module.redis_cluster_region1,
    module.redis_cluster_region2,
    module.vpc_peering_mesh,
    null_resource.verify_dns_resolution
  ]
}

#==============================================================================
# RERC (RedisEnterpriseRemoteCluster) CONFIGURATION
#==============================================================================
# Per Redis docs: https://redis.io/docs/latest/operate/kubernetes/active-active/prepare-clusters/
# Each cluster needs RERCs for ALL participating clusters:
# - LOCAL RERC: References local REC (recName matches local cluster)
# - REMOTE RERCs: Reference remote clusters via apiFqdnUrl
#==============================================================================

# Region1: LOCAL RERC (references own cluster)
module "rerc_region1_local" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc"

  providers = {
    kubectl = kubectl.region1
  }

  rerc_name             = "rerc-${local.region_list[0]}"
  namespace             = var.redis_enterprise_namespace
  local_rec_name        = var.cluster_name # Matches local REC = LOCAL
  remote_api_fqdn       = "api-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  remote_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  remote_secret_name    = module.rerc_credentials_region1_local[0].secret_name
  eks_cluster_name      = module.redis_cluster_region1.eks_cluster_name
  aws_region            = local.region_list[0]

  depends_on = [module.rerc_credentials_region1_local, module.dns_region1]
}

# Region1: REMOTE RERC (references region2)
module "rerc_region1_to_region2" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc"

  providers = {
    kubectl = kubectl.region1
  }

  rerc_name             = "rerc-${local.region_list[1]}"
  namespace             = var.redis_enterprise_namespace
  local_rec_name        = var.cluster_name
  remote_api_fqdn       = "api-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  remote_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  remote_secret_name    = module.rerc_credentials_region1_remote[0].secret_name
  eks_cluster_name      = module.redis_cluster_region1.eks_cluster_name
  aws_region            = local.region_list[0]

  depends_on = [module.rerc_credentials_region1_remote, module.dns_region2]
}

# Region2: LOCAL RERC (references own cluster)
module "rerc_region2_local" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc"

  providers = {
    kubectl = kubectl.region2
  }

  rerc_name             = "rerc-${local.region_list[1]}"
  namespace             = var.redis_enterprise_namespace
  local_rec_name        = var.cluster_name # Matches local REC = LOCAL
  remote_api_fqdn       = "api-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  remote_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"
  remote_secret_name    = module.rerc_credentials_region2_local[0].secret_name
  eks_cluster_name      = module.redis_cluster_region2[0].eks_cluster_name
  aws_region            = local.region_list[1]

  depends_on = [module.rerc_credentials_region2_local, module.dns_region2]
}

# Region2: REMOTE RERC (references region1)
module "rerc_region2_to_region1" {
  count  = length(local.region_list) > 1 ? 1 : 0
  source = "./modules/rerc"

  providers = {
    kubectl = kubectl.region2
  }

  rerc_name             = "rerc-${local.region_list[0]}"
  namespace             = var.redis_enterprise_namespace
  local_rec_name        = var.cluster_name
  remote_api_fqdn       = "api-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  remote_db_fqdn_suffix = "-db-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
  remote_secret_name    = module.rerc_credentials_region2_remote[0].secret_name
  eks_cluster_name      = module.redis_cluster_region2[0].eks_cluster_name
  aws_region            = local.region_list[1]

  depends_on = [module.rerc_credentials_region2_remote, module.dns_region1]
}

#==============================================================================
# CROSS-CLUSTER API CONNECTIVITY CHECK
#==============================================================================
# Before creating the REAADB, verify each cluster can reach the other's API
# endpoint through the full path: DNS → NLB → nginx ingress → REC API (9443).
# The CRDB coordinator needs this path to provision remote BDB instances.
#==============================================================================

resource "null_resource" "verify_cross_cluster_connectivity" {
  count = var.create_aa_database && length(local.region_list) > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      echo "=== Verifying cross-cluster API connectivity ==="

      EAST_KUBECONFIG=$(mktemp)
      WEST_KUBECONFIG=$(mktemp)
      trap "rm -f $EAST_KUBECONFIG $WEST_KUBECONFIG" EXIT

      aws eks update-kubeconfig --region ${local.region_list[0]} --name ${module.redis_cluster_region1.eks_cluster_name} --kubeconfig "$EAST_KUBECONFIG" 2>&1
      aws eks update-kubeconfig --region ${local.region_list[1]} --name ${module.redis_cluster_region2[0].eks_cluster_name} --kubeconfig "$WEST_KUBECONFIG" 2>&1

      REGION1_API="api-${local.name_prefix}-${local.region_list[0]}.${data.aws_route53_zone.main.name}"
      REGION2_API="api-${local.name_prefix}-${local.region_list[1]}.${data.aws_route53_zone.main.name}"

      MAX_ATTEMPTS=18
      SLEEP_INTERVAL=10

      # Test: Region1 pod → Region2 API (port 443 - used by CRDB coordinator via ingress)
      echo "Testing: ${local.region_list[0]} → $REGION2_API:443 (ingress path for CRDB)..."
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        RESULT=$(kubectl --kubeconfig "$EAST_KUBECONFIG" exec -n ${var.redis_enterprise_namespace} ${var.cluster_name}-0 -c redis-enterprise-node -- curl -sk --connect-timeout 5 -o /dev/null -w "%%{http_code}" "https://$REGION2_API:443/v1/cluster" 2>/dev/null || echo "000")
        if [ "$RESULT" != "000" ]; then
          echo "  Success: HTTP $RESULT from $REGION2_API:443"
          break
        fi
        ATTEMPT=$((ATTEMPT+1))
        echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS: no response on :443, waiting $${SLEEP_INTERVAL}s..."
        sleep $SLEEP_INTERVAL
      done
      if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "ERROR: ${local.region_list[0]} cannot reach $REGION2_API:443"
        echo "Check: security group allows port 443 from 0.0.0.0/0, nginx ingress, DNS resolution"
        exit 1
      fi

      # Test: Region2 pod → Region1 API (port 443 - used by CRDB coordinator via ingress)
      echo "Testing: ${local.region_list[1]} → $REGION1_API:443 (ingress path for CRDB)..."
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        RESULT=$(kubectl --kubeconfig "$WEST_KUBECONFIG" exec -n ${var.redis_enterprise_namespace} ${var.cluster_name}-0 -c redis-enterprise-node -- curl -sk --connect-timeout 5 -o /dev/null -w "%%{http_code}" "https://$REGION1_API:443/v1/cluster" 2>/dev/null || echo "000")
        if [ "$RESULT" != "000" ]; then
          echo "  Success: HTTP $RESULT from $REGION1_API:443"
          break
        fi
        ATTEMPT=$((ATTEMPT+1))
        echo "  Attempt $ATTEMPT/$MAX_ATTEMPTS: no response on :443, waiting $${SLEEP_INTERVAL}s..."
        sleep $SLEEP_INTERVAL
      done
      if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "ERROR: ${local.region_list[1]} cannot reach $REGION1_API:443"
        echo "Check: security group allows port 443 from 0.0.0.0/0, nginx ingress, DNS resolution"
        exit 1
      fi

      echo "=== Cross-cluster connectivity verified ==="
    EOF
  }

  depends_on = [
    module.rerc_region1_local,
    module.rerc_region1_to_region2,
    module.rerc_region2_local,
    module.rerc_region2_to_region1,
    null_resource.verify_dns_resolution
  ]
}

#==============================================================================
# GLOBAL DATABASE SECRET - REGION 2
#==============================================================================
# Per Redis docs on global database secrets, the databaseSecretName secret must
# exist in ALL participating clusters before the REAADB is created. The reaadb
# module only creates it in region1 (via kubernetes.region1 provider). Create
# the same secret in region2 here so the operator can sync the REAADB there.
#==============================================================================

resource "kubernetes_secret" "aa_database_secret_region2" {
  count = var.create_aa_database && length(local.region_list) > 1 && var.aa_database_password != "" ? 1 : 0

  provider = kubernetes.region2

  metadata {
    name      = "${var.aa_database_name}-secret"
    namespace = var.redis_enterprise_namespace
  }

  type = "Opaque"

  data = {
    password = var.aa_database_password
  }

  depends_on = [
    module.redis_cluster_region2,
    null_resource.verify_cross_cluster_connectivity
  ]
}

#==============================================================================
# REAADB (Active-Active Database)
#==============================================================================
# Creates the Active-Active database across all participating clusters.
# Per Redis docs: https://redis.io/docs/latest/operate/kubernetes/active-active/create-reaadb/
# participatingClusters must reference RERC names (not REC names)
#==============================================================================

module "aa_database" {
  count  = var.create_aa_database && length(local.region_list) > 1 ? 1 : 0
  source = "./modules/reaadb"

  providers = {
    kubernetes = kubernetes.region1
    kubectl    = kubectl.region1
  }

  create_database = var.create_aa_database
  database_name   = var.aa_database_name
  namespace       = var.redis_enterprise_namespace

  # Participating clusters - MUST use RERC names (not REC names)
  # Per Redis docs, each entry references an RERC resource
  participating_clusters = [
    { name = "rerc-${local.region_list[0]}" }, # RERC for region1
    { name = "rerc-${local.region_list[1]}" }  # RERC for region2
  ]

  # EKS cluster context (for kubectl in local-exec provisioners)
  eks_cluster_name = module.redis_cluster_region1.eks_cluster_name
  aws_region       = local.region_list[0]

  # Database configuration
  # shard_count=1 with replication=true = 2 shards per region = 4 total (within license limit)
  database_secret_name = var.aa_database_password != "" ? "${var.aa_database_name}-secret" : ""
  database_password    = var.aa_database_password
  memory_size          = var.aa_database_memory
  shard_count          = var.aa_database_shard_count
  replication          = var.aa_database_replication
  tls_mode             = var.aa_database_tls_mode
  modules_list         = var.aa_database_modules

  # Wait for ALL RERCs to be ready (both local and remote in both regions)
  rerc_dependencies = [
    module.rerc_region1_local[0].rerc_ready,
    module.rerc_region1_to_region2[0].rerc_ready,
    module.rerc_region2_local[0].rerc_ready,
    module.rerc_region2_to_region1[0].rerc_ready
  ]

  depends_on = [
    module.rerc_region1_local,
    module.rerc_region1_to_region2,
    module.rerc_region2_local,
    module.rerc_region2_to_region1,
    null_resource.verify_cross_cluster_connectivity,
    kubernetes_secret.aa_database_secret_region2,
    # Ensure both RECs are in Running state before the admission webhook sees REAADB
    module.redis_cluster_region1,
    module.redis_cluster_region2,
  ]
}
