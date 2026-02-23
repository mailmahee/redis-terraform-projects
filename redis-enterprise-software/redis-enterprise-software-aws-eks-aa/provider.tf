#==============================================================================
# MULTI-REGION PROVIDER CONFIGURATION
#==============================================================================
# Configures AWS providers for each region and corresponding Kubernetes/Helm
# providers for each EKS cluster.
# Note: local.region_list is defined in main.tf
#==============================================================================

#==============================================================================
# AWS PROVIDERS (one per region)
#==============================================================================

provider "aws" {
  alias  = "region1"
  region = local.region_list[0]

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "Terraform"
        Owner       = var.owner
      },
      var.tags
    )
  }
}

provider "aws" {
  alias  = "region2"
  region = length(local.region_list) > 1 ? local.region_list[1] : local.region_list[0]

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "Terraform"
        Owner       = var.owner
      },
      var.tags
    )
  }
}

#==============================================================================
# KUBERNETES PROVIDERS (one per region/cluster)
#==============================================================================
# These are configured after the EKS clusters are created.
# The configuration uses data sources to get cluster information.
#==============================================================================

# Region 1 Kubernetes provider
provider "kubernetes" {
  alias = "region1"

  host                   = module.redis_cluster_region1.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.redis_cluster_region1.eks_cluster_name,
      "--region",
      local.region_list[0]
    ]
  }
}

# Region 2 Kubernetes provider (only used when 2 regions configured)
provider "kubernetes" {
  alias = "region2"

  host                   = length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_endpoint : module.redis_cluster_region1.eks_cluster_endpoint
  cluster_ca_certificate = length(local.region_list) > 1 ? base64decode(module.redis_cluster_region2[0].eks_cluster_certificate_authority_data) : base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_name : module.redis_cluster_region1.eks_cluster_name,
      "--region",
      length(local.region_list) > 1 ? local.region_list[1] : local.region_list[0]
    ]
  }
}

#==============================================================================
# HELM PROVIDERS (one per region/cluster)
#==============================================================================

provider "helm" {
  alias = "region1"

  kubernetes {
    host                   = module.redis_cluster_region1.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.redis_cluster_region1.eks_cluster_name,
        "--region",
        local.region_list[0]
      ]
    }
  }
}

provider "helm" {
  alias = "region2"

  kubernetes {
    host                   = length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_endpoint : module.redis_cluster_region1.eks_cluster_endpoint
    cluster_ca_certificate = length(local.region_list) > 1 ? base64decode(module.redis_cluster_region2[0].eks_cluster_certificate_authority_data) : base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_name : module.redis_cluster_region1.eks_cluster_name,
        "--region",
        length(local.region_list) > 1 ? local.region_list[1] : local.region_list[0]
      ]
    }
  }
}

#==============================================================================
# KUBECTL PROVIDERS (one per region/cluster)
#==============================================================================

provider "kubectl" {
  alias = "region1"

  host                   = module.redis_cluster_region1.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.redis_cluster_region1.eks_cluster_name,
      "--region",
      local.region_list[0]
    ]
  }
}

provider "kubectl" {
  alias = "region2"

  host                   = length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_endpoint : module.redis_cluster_region1.eks_cluster_endpoint
  cluster_ca_certificate = length(local.region_list) > 1 ? base64decode(module.redis_cluster_region2[0].eks_cluster_certificate_authority_data) : base64decode(module.redis_cluster_region1.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      length(local.region_list) > 1 ? module.redis_cluster_region2[0].eks_cluster_name : module.redis_cluster_region1.eks_cluster_name,
      "--region",
      length(local.region_list) > 1 ? local.region_list[1] : local.region_list[0]
    ]
  }
}
