#==============================================================================
# SINGLE REGION EKS + REDIS ENTERPRISE WRAPPER MODULE
#==============================================================================
# This module deploys a complete EKS cluster with Redis Enterprise in a single
# region. Used by the multi-region Active-Active orchestration layer.
#==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Name prefix includes region for uniqueness
  name_prefix = "${var.user_prefix}-${var.cluster_name}-${var.region}"

  # Use specified AZs if provided, otherwise auto-select
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : [
    "${var.region}a",
    "${var.region}b",
    "${var.region}c"
  ]

  # Validate instance types for Redis Flex
  flex_compatible_instances = ["i3.xlarge", "i3.2xlarge", "i3.4xlarge", "i3.8xlarge", "i3.16xlarge",
  "i4i.xlarge", "i4i.2xlarge", "i4i.4xlarge", "i4i.8xlarge", "i4i.16xlarge"]

  using_flex_instance = length([for type in var.node_instance_types : type if contains(local.flex_compatible_instances, type)]) > 0

  tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ClusterName = var.cluster_name
      Region      = var.region
    }
  )
}

#==============================================================================
# VALIDATION: Redis Flex requires i3/i4i instances with NVMe SSDs
#==============================================================================

resource "null_resource" "validate_flex_config" {
  count = var.enable_redis_flex && !local.using_flex_instance ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.enable_redis_flex || local.using_flex_instance
      error_message = "Redis Flex requires i3.* or i4i.* instance types with local NVMe SSDs. Current: ${join(", ", var.node_instance_types)}"
    }
  }
}

#==============================================================================
# VPC MODULE
#==============================================================================

module "vpc" {
  source = "../vpc"

  name_prefix          = local.name_prefix
  cluster_name         = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = local.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = false # Using public subnets for worker nodes

  tags = local.tags
}

#==============================================================================
# EKS CLUSTER MODULE
#==============================================================================

module "eks" {
  source = "../eks_cluster"

  cluster_name                    = local.name_prefix
  kubernetes_version              = var.kubernetes_version
  vpc_id                          = module.vpc.vpc_id
  public_subnet_ids               = module.vpc.public_subnet_ids
  private_subnet_ids              = module.vpc.private_subnet_ids
  cluster_endpoint_public_access  = var.cluster_endpoint_public_access
  cluster_endpoint_private_access = var.cluster_endpoint_private_access
  aws_region                      = var.region

  tags = local.tags

  depends_on = [module.vpc]
}

#==============================================================================
# EKS NODE GROUP MODULE
#==============================================================================

module "eks_node_group" {
  source = "../eks_node_group"

  cluster_name              = module.eks.cluster_name
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.public_subnet_ids
  cluster_security_group_id = module.eks.cluster_security_group_id
  instance_types            = var.node_instance_types
  desired_size              = var.node_desired_size
  min_size                  = var.node_min_size
  max_size                  = var.node_max_size
  disk_size                 = var.node_disk_size

  # Allow traffic from peer regions for Active-Active
  peer_region_cidrs = var.peer_region_cidrs

  tags = local.tags

  depends_on = [module.eks]
}

#==============================================================================
# EBS CSI DRIVER MODULE
#==============================================================================

module "ebs_csi_driver" {
  source = "../ebs_csi_driver"

  cluster_name       = module.eks.cluster_name
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_issuer_url    = module.eks.cluster_oidc_issuer_url
  storage_class_name = var.redis_cluster_storage_class
  set_as_default     = true

  tags = local.tags

  depends_on = [module.eks_node_group]
}

#==============================================================================
# LOCAL STORAGE PROVISIONER (for Redis Flex NVMe discovery)
#==============================================================================

module "local_storage_provisioner" {
  source = "../local_storage_provisioner"

  enable_provisioner = var.enable_redis_flex
  cluster_ready      = module.ebs_csi_driver
}

#==============================================================================
# REDIS ENTERPRISE OPERATOR MODULE
#==============================================================================

module "redis_operator" {
  source = "../redis_operator"

  namespace        = var.redis_enterprise_namespace
  operator_version = var.redis_operator_version
  cluster_name     = module.eks.cluster_name
  aws_region       = var.region

  depends_on = [module.ebs_csi_driver]
}

#==============================================================================
# REDIS ENTERPRISE CLUSTER MODULE
#==============================================================================

#==============================================================================
# NGINX INGRESS CONTROLLER (Required for Active-Active)
#==============================================================================
# Deploys nginx-ingress with SSL passthrough for Redis Enterprise API access.
# Per Redis docs: https://redis.io/docs/latest/operate/kubernetes/networking/ingressorroutespec/
#==============================================================================

resource "helm_release" "nginx_ingress" {
  count = var.enable_active_active ? 1 : 0

  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  namespace        = "ingress-nginx"
  create_namespace = true

  # Configure for AWS EKS with NLB
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  # CRITICAL: Enable SSL passthrough for Redis Enterprise API (port 9443)
  set {
    name  = "controller.extraArgs.enable-ssl-passthrough"
    value = ""
  }

  # Expose port 9443 as a TCP service on the NLB.
  # The CRDB coordinator connects to remote clusters on port 9443 (the Redis
  # Enterprise API default). Without this, the NLB only exposes 80/443 and
  # the CRDB provisioning times out trying to reach the remote cluster.
  set {
    name  = "tcp.9443"
    value = "${var.redis_enterprise_namespace}/${var.cluster_name}:9443"
  }

  # High availability configuration
  set {
    name  = "controller.replicaCount"
    value = "2"
  }

  wait    = true
  timeout = 600

  depends_on = [module.eks_node_group]
}

# Wait for nginx ingress NLB to get a hostname assigned.
# The helm_release wait=true ensures the pods are ready, but the NLB
# hostname can take additional time to be assigned by AWS.
# Uses a dedicated kubeconfig file so both regions can run in parallel
# without conflicting on the default kubectl context.
resource "null_resource" "wait_for_nginx_lb" {
  count = var.enable_active_active ? 1 : 0

  depends_on = [helm_release.nginx_ingress]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      KUBECONFIG_FILE=$(mktemp)
      trap "rm -f $KUBECONFIG_FILE" EXIT

      echo "Configuring kubectl for EKS cluster ${module.eks.cluster_name} in ${var.region}..."
      aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name} --kubeconfig "$KUBECONFIG_FILE" 2>&1

      echo "Waiting for nginx ingress NLB hostname to be assigned..."
      MAX_ATTEMPTS=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        HOSTNAME=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        if [ -n "$HOSTNAME" ]; then
          echo "NLB hostname assigned: $HOSTNAME"
          exit 0
        fi
        ATTEMPT=$((ATTEMPT+1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: NLB hostname not yet assigned, waiting 10s..."
        sleep 10
      done
      echo "ERROR: NLB hostname was not assigned within 5 minutes."
      echo "Check: kubectl get svc ingress-nginx-controller -n ingress-nginx"
      exit 1
    EOF
  }
}

# Data source to get the nginx ingress LoadBalancer hostname
# Only read after the NLB hostname is confirmed to exist
data "kubernetes_service" "nginx_ingress" {
  count = var.enable_active_active ? 1 : 0

  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [null_resource.wait_for_nginx_lb]
}

#==============================================================================
# REDIS ENTERPRISE CLUSTER MODULE
#==============================================================================

module "redis_cluster" {
  source = "../redis_cluster"

  cluster_name                 = var.cluster_name
  eks_cluster_name             = module.eks.cluster_name
  aws_region                   = var.region
  namespace                    = module.redis_operator.namespace
  node_count                   = var.redis_cluster_nodes
  admin_username               = var.redis_cluster_username
  admin_password               = var.redis_cluster_password
  node_memory_limit            = var.redis_cluster_memory
  storage_class_name           = module.ebs_csi_driver.storage_class_name
  storage_size                 = var.redis_cluster_storage_size
  redis_enterprise_version_tag = var.redis_enterprise_version_tag

  # Service type configuration
  ui_service_type        = var.ui_internal_lb_enabled ? "LoadBalancer" : var.redis_ui_service_type
  ui_service_annotations = var.ui_internal_lb_enabled ? var.ui_service_annotations : {}
  database_service_type  = var.redis_database_service_type

  # License configuration
  license_secret_name = var.redis_license_secret_name

  # Redis Flex (Auto Tiering) configuration
  enable_redis_flex          = var.enable_redis_flex
  redis_flex_storage_class   = var.redis_flex_storage_class
  redis_flex_flash_disk_size = var.redis_flex_flash_disk_size
  redis_flex_storage_driver  = var.redis_flex_storage_driver

  # Ingress/Route configuration
  enable_ingress      = var.redis_enable_ingress
  api_fqdn_url        = var.redis_api_fqdn_url
  db_fqdn_suffix      = var.redis_db_fqdn_suffix
  ingress_method      = var.redis_ingress_method
  ingress_annotations = var.redis_ingress_annotations

  # Operator version (needed to fetch matching webhook.yaml for admission controller)
  operator_version = var.redis_operator_version

  # Active-Active configuration
  enable_active_active = var.enable_active_active

  depends_on = [
    module.redis_operator,
    module.local_storage_provisioner,
    helm_release.nginx_ingress,
    null_resource.wait_for_nginx_lb
  ]
}
