#==============================================================================
# SINGLE-REGION REDIS ENTERPRISE ON AWS EKS
#==============================================================================
# This is a wrapper that deploys the redis-enterprise-eks module in a single region
#==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

#==============================================================================
# REDIS ENTERPRISE EKS MODULE
#==============================================================================

module "redis_enterprise_eks" {
  source = "../modules/redis-enterprise-eks"

  # Basic Configuration
  aws_region   = var.aws_region
  user_prefix  = var.user_prefix
  cluster_name = var.cluster_name
  project      = var.project
  environment  = var.environment
  owner        = var.owner
  tags         = var.tags

  # Network Configuration
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  enable_nat_gateway  = var.enable_nat_gateway
  single_nat_gateway  = var.single_nat_gateway

  # EKS Configuration
  eks_cluster_version = var.eks_cluster_version
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  # Redis Enterprise Configuration
  redis_operator_version     = var.redis_operator_version
  redis_cluster_nodes        = var.redis_cluster_nodes
  redis_cluster_username     = var.redis_cluster_username
  redis_cluster_password     = var.redis_cluster_password
  redis_persistent_storage   = var.redis_persistent_storage
  redis_storage_size         = var.redis_storage_size
  redis_node_memory          = var.redis_node_memory
  redis_node_cpu             = var.redis_node_cpu
  redis_ui_service_type      = var.redis_ui_service_type

  # Sample Database Configuration
  create_sample_database     = var.create_sample_database
  sample_db_name             = var.sample_db_name
  sample_db_port             = var.sample_db_port
  sample_db_memory           = var.sample_db_memory
  sample_db_replication      = var.sample_db_replication
  sample_db_shard_count      = var.sample_db_shard_count
  sample_db_service_type     = var.sample_db_service_type

  # External Access Configuration
  external_access_type       = var.external_access_type
  enable_tls                 = var.enable_tls
  redis_enable_ingress       = var.redis_enable_ingress
  redis_ingress_method       = var.redis_ingress_method
  redis_api_fqdn_url         = var.redis_api_fqdn_url
  redis_db_fqdn_suffix       = var.redis_db_fqdn_suffix

  # Redis Flex Configuration
  enable_redis_flex          = var.enable_redis_flex

  # Bastion Configuration
  create_bastion             = var.create_bastion
  bastion_instance_type      = var.bastion_instance_type
  bastion_key_name           = var.bastion_key_name
  bastion_allowed_cidr_blocks = var.bastion_allowed_cidr_blocks
}

