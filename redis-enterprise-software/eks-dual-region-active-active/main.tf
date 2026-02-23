#==============================================================================
# DUAL-REGION REDIS ENTERPRISE ON AWS EKS
#==============================================================================
# This wrapper deploys the redis-enterprise-eks module in two regions
# with VPC peering between them
#==============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      configuration_aliases = [
        aws.region1,
        aws.region2
      ]
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
      configuration_aliases = [
        kubernetes.region1,
        kubernetes.region2
      ]
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11"
      configuration_aliases = [
        helm.region1,
        helm.region2
      ]
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
      configuration_aliases = [
        kubectl.region1,
        kubectl.region2
      ]
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

#==============================================================================
# LOCALS
#==============================================================================

locals {
  region1 = var.region1
  region2 = var.region2
}

#==============================================================================
# REGION 1 - REDIS ENTERPRISE EKS
#==============================================================================

module "region1" {
  source = "../modules/redis-enterprise-eks"

  providers = {
    aws        = aws.region1
    kubernetes = kubernetes.region1
    helm       = helm.region1
    kubectl    = kubectl.region1
  }

  # Basic Configuration
  aws_region   = local.region1
  user_prefix  = "${var.user_prefix}-r1"
  cluster_name = "rec-${local.region1}"  # Will become: <user_prefix>-rec-<region>
  project      = var.project
  environment  = var.environment
  owner        = var.owner
  tags         = var.tags

  # Network Configuration
  vpc_cidr             = var.region1_vpc_cidr
  public_subnet_cidrs  = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
  private_subnet_cidrs = ["10.1.4.0/24", "10.1.5.0/24", "10.1.6.0/24"]
  availability_zones   = var.region1_availability_zones

  # EKS Configuration
  kubernetes_version  = var.eks_cluster_version
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  # Redis Enterprise Configuration
  redis_operator_version     = var.redis_operator_version
  redis_cluster_nodes        = var.redis_nodes
  redis_cluster_username     = var.redis_cluster_username
  redis_cluster_password     = var.redis_cluster_password
  redis_cluster_memory       = var.redis_node_memory
  redis_cluster_storage_size = var.redis_storage_size
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
  ingress_domain             = var.ingress_domain

  # Cluster-to-Cluster Ingress (for Active-Active)
  redis_enable_ingress       = var.redis_enable_ingress
  redis_ingress_method       = var.redis_ingress_method
  redis_api_fqdn_url         = var.region1_redis_api_fqdn_url
  redis_db_fqdn_suffix       = var.region1_redis_db_fqdn_suffix

  # DNS Configuration (for automated Route53 DNS record creation)
  dns_hosted_zone_id         = var.dns_hosted_zone_id
  dns_ttl                    = var.dns_ttl
  validate_dns_propagation   = var.validate_dns_propagation

  # Redis Flex Configuration
  enable_redis_flex          = var.enable_redis_flex

  # Bastion Configuration
  create_bastion             = var.create_bastion
  bastion_instance_type      = var.bastion_instance_type
  ec2_key_name               = var.bastion_key_name
  bastion_ssh_cidr_blocks    = var.bastion_allowed_cidr_blocks
}

#==============================================================================
# REGION 2 - REDIS ENTERPRISE EKS
#==============================================================================

module "region2" {
  source = "../modules/redis-enterprise-eks"

  providers = {
    aws        = aws.region2
    kubernetes = kubernetes.region2
    helm       = helm.region2
    kubectl    = kubectl.region2
  }

  # Basic Configuration
  aws_region   = local.region2
  user_prefix  = "${var.user_prefix}-r2"
  cluster_name = "rec-${local.region2}"  # Will become: <user_prefix>-rec-<region>
  project      = var.project
  environment  = var.environment
  owner        = var.owner
  tags         = var.tags

  # Network Configuration
  vpc_cidr             = var.region2_vpc_cidr
  public_subnet_cidrs  = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  private_subnet_cidrs = ["10.2.4.0/24", "10.2.5.0/24", "10.2.6.0/24"]
  availability_zones   = var.region2_availability_zones

  # EKS Configuration
  kubernetes_version  = var.eks_cluster_version
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_disk_size      = var.node_disk_size

  # Redis Enterprise Configuration
  redis_operator_version     = var.redis_operator_version
  redis_cluster_nodes        = var.redis_nodes
  redis_cluster_username     = var.redis_cluster_username
  redis_cluster_password     = var.redis_cluster_password
  redis_cluster_memory       = var.redis_node_memory
  redis_cluster_storage_size = var.redis_storage_size
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
  ingress_domain             = var.ingress_domain

  # Cluster-to-Cluster Ingress (for Active-Active)
  redis_enable_ingress       = var.redis_enable_ingress
  redis_ingress_method       = var.redis_ingress_method
  redis_api_fqdn_url         = var.region2_redis_api_fqdn_url
  redis_db_fqdn_suffix       = var.region2_redis_db_fqdn_suffix

  # DNS Configuration (for automated Route53 DNS record creation)
  dns_hosted_zone_id         = var.dns_hosted_zone_id
  dns_ttl                    = var.dns_ttl
  validate_dns_propagation   = var.validate_dns_propagation

  # Redis Flex Configuration
  enable_redis_flex          = var.enable_redis_flex

  # Bastion Configuration
  create_bastion             = var.create_bastion
  bastion_instance_type      = var.bastion_instance_type
  ec2_key_name               = var.bastion_key_name
  bastion_ssh_cidr_blocks    = var.bastion_allowed_cidr_blocks
}

#==============================================================================
# VPC PEERING - CONNECT REGION 1 AND REGION 2
#==============================================================================

# Create VPC peering connection from region1 to region2
resource "aws_vpc_peering_connection" "region1_to_region2" {
  provider = aws.region1

  vpc_id      = module.region1.vpc_id
  peer_vpc_id = module.region2.vpc_id
  peer_region = local.region2
  auto_accept = false

  tags = {
    Name = "${var.user_prefix}-vpc-peering-r1-to-r2"
  }
}

# Accept the peering connection in region2
resource "aws_vpc_peering_connection_accepter" "region2_accept" {
  provider = aws.region2

  vpc_peering_connection_id = aws_vpc_peering_connection.region1_to_region2.id
  auto_accept               = true

  tags = {
    Name = "${var.user_prefix}-vpc-peering-r2-accept"
  }
}

# Add routes in region1 private route tables to region2 VPC
resource "aws_route" "region1_to_region2" {
  provider = aws.region1
  count    = length(module.region1.private_route_table_ids)

  route_table_id            = module.region1.private_route_table_ids[count.index]
  destination_cidr_block    = var.region2_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.region1_to_region2.id
}

# Add routes in region2 private route tables to region1 VPC
resource "aws_route" "region2_to_region1" {
  provider = aws.region2
  count    = length(module.region2.private_route_table_ids)

  route_table_id            = module.region2.private_route_table_ids[count.index]
  destination_cidr_block    = var.region1_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.region1_to_region2.id
}

