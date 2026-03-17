#==============================================================================
# PROVIDER CONFIGURATION - DUAL REGION
#==============================================================================

#------------------------------------------------------------------------------
# AWS PROVIDERS
#------------------------------------------------------------------------------

provider "aws" {
  alias   = "region1"
  region  = var.region1
  profile = var.aws_profile

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "Terraform"
        Owner       = var.owner
        Region      = "region1"
      },
      var.tags
    )
  }
}

provider "aws" {
  alias   = "region2"
  region  = var.region2
  profile = var.aws_profile

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "Terraform"
        Owner       = var.owner
        Region      = "region2"
      },
      var.tags
    )
  }
}

#------------------------------------------------------------------------------
# KUBERNETES PROVIDERS
#------------------------------------------------------------------------------

provider "kubernetes" {
  alias = "region1"

  host                   = module.region1.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.region1.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.region1.eks_cluster_name,
      "--region",
      var.region1,
      "--profile",
      var.aws_profile
    ]
  }
}

provider "kubernetes" {
  alias = "region2"

  host                   = module.region2.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.region2.eks_cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.region2.eks_cluster_name,
      "--region",
      var.region2,
      "--profile",
      var.aws_profile
    ]
  }
}

#------------------------------------------------------------------------------
# HELM PROVIDERS
#------------------------------------------------------------------------------

provider "helm" {
  alias = "region1"

  kubernetes {
    host                   = module.region1.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.region1.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.region1.eks_cluster_name,
        "--region",
        var.region1,
        "--profile",
        var.aws_profile
      ]
    }
  }
}

provider "helm" {
  alias = "region2"

  kubernetes {
    host                   = module.region2.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.region2.eks_cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.region2.eks_cluster_name,
        "--region",
        var.region2,
        "--profile",
        var.aws_profile
      ]
    }
  }
}

#------------------------------------------------------------------------------
# KUBECTL PROVIDERS
#------------------------------------------------------------------------------

provider "kubectl" {
  alias = "region1"

  host                   = module.region1.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.region1.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.region1.eks_cluster_name,
      "--region",
      var.region1,
      "--profile",
      var.aws_profile
    ]
  }
}

provider "kubectl" {
  alias = "region2"

  host                   = module.region2.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.region2.eks_cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.region2.eks_cluster_name,
      "--region",
      var.region2,
      "--profile",
      var.aws_profile
    ]
  }
}

