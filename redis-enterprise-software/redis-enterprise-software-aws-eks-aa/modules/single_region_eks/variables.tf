#==============================================================================
# PROJECT IDENTIFICATION
#==============================================================================

variable "project" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "redis-enterprise-eks-aa"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner name for resource tagging"
  type        = string
}

variable "user_prefix" {
  description = "User prefix for unique resource naming"
  type        = string
}

variable "cluster_name" {
  description = "Redis Enterprise cluster name"
  type        = string
  default     = "redis-ent-eks"
}

variable "region" {
  description = "AWS region for this deployment"
  type        = string
}

#==============================================================================
# NETWORK CONFIGURATION
#==============================================================================

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones to use. If empty, will auto-select based on region"
  type        = list(string)
  default     = []
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "peer_region_cidrs" {
  description = "List of peer region VPC CIDRs for Active-Active cross-region communication"
  type        = list(string)
  default     = []
}

#==============================================================================
# EKS CLUSTER CONFIGURATION
#==============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private access to EKS cluster endpoint"
  type        = bool
  default     = true
}

#==============================================================================
# EKS NODE GROUP CONFIGURATION
#==============================================================================

variable "node_instance_types" {
  description = "EC2 instance types for EKS worker nodes"
  type        = list(string)
  default     = ["t3.xlarge"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 3
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 6
}

variable "node_disk_size" {
  description = "Disk size in GB for worker nodes"
  type        = number
  default     = 100
}

#==============================================================================
# REDIS ENTERPRISE CONFIGURATION
#==============================================================================

variable "redis_enterprise_namespace" {
  description = "Kubernetes namespace for Redis Enterprise"
  type        = string
  default     = "redis-enterprise"
}

variable "redis_operator_version" {
  description = "Redis Enterprise operator version (Helm chart version)"
  type        = string
  default     = "v7.4.6-2"
}

variable "redis_cluster_nodes" {
  description = "Number of Redis Enterprise cluster nodes"
  type        = number
  default     = 3
}

variable "redis_cluster_username" {
  description = "Redis Enterprise cluster admin username (email format)"
  type        = string
  default     = "admin@admin.com"
}

variable "redis_cluster_password" {
  description = "Redis Enterprise cluster admin password (alphanumeric only)"
  type        = string
  sensitive   = true
}

variable "redis_cluster_memory" {
  description = "Memory limit for each Redis Enterprise node (e.g., '4Gi', '8Gi')"
  type        = string
  default     = "4Gi"
}

variable "redis_cluster_storage_size" {
  description = "Persistent storage size for each Redis Enterprise node (e.g., '50Gi', '100Gi')"
  type        = string
  default     = "50Gi"
}

variable "redis_cluster_storage_class" {
  description = "Storage class for Redis Enterprise persistent volumes"
  type        = string
  default     = "gp3"
}

variable "redis_enterprise_version_tag" {
  description = "Redis Enterprise image tag (e.g., 7.4.6-xx) matching the operator"
  type        = string
  default     = "7.4.6-22"
}

#==============================================================================
# REDIS FLEX (AUTO TIERING) CONFIGURATION
#==============================================================================

variable "enable_redis_flex" {
  description = "Enable Redis Flex (Auto Tiering) for flash storage. Requires local NVMe SSDs on worker nodes. Incompatible with Active-Active."
  type        = bool
  default     = false
}

variable "redis_flex_storage_class" {
  description = "Storage class for Redis Flex flash storage (must be local NVMe SSDs, not EBS)"
  type        = string
  default     = "local-scsi"
}

variable "redis_flex_flash_disk_size" {
  description = "Flash disk size per node for Redis Flex (e.g., '100G', '500G')"
  type        = string
  default     = "100G"
}

variable "redis_flex_storage_driver" {
  description = "Storage driver for Redis Flex: 'speedb' (default) or 'rocksdb'"
  type        = string
  default     = "speedb"
}

#==============================================================================
# REDIS UI AND DATABASE SERVICE CONFIGURATION
#==============================================================================

variable "redis_ui_service_type" {
  description = "Service type for Redis Enterprise UI (ClusterIP for internal, LoadBalancer for external)"
  type        = string
  default     = "ClusterIP"
}

variable "ui_internal_lb_enabled" {
  description = "If true, exposes the UI via an internal AWS LoadBalancer"
  type        = bool
  default     = false
}

variable "ui_service_annotations" {
  description = "Annotations to apply to the UI service (used when enabling an internal LB)."
  type        = map(string)
  default = {
    "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
  }
}

variable "redis_database_service_type" {
  description = "Default service type for databases (ClusterIP for internal, LoadBalancer for external)"
  type        = string
  default     = "ClusterIP"
}

variable "redis_license_secret_name" {
  description = "Name of Kubernetes secret containing Redis Enterprise license (optional)"
  type        = string
  default     = ""
}

#==============================================================================
# REDIS INGRESS CONFIGURATION (required for Active-Active)
#==============================================================================

variable "redis_enable_ingress" {
  description = "Enable ingress/route configuration for external access"
  type        = bool
  default     = false
}

variable "redis_api_fqdn_url" {
  description = "FQDN for Redis Enterprise API (required for Active-Active)"
  type        = string
  default     = ""
}

variable "redis_db_fqdn_suffix" {
  description = "FQDN suffix for database access (required for Active-Active)"
  type        = string
  default     = ""
}

variable "redis_ingress_method" {
  description = "Ingress method: 'ingress' for NGINX/HAProxy or 'openShiftRoute'"
  type        = string
  default     = "ingress"
}

variable "redis_ingress_annotations" {
  description = "Annotations for ingress controller"
  type        = map(string)
  default = {
    "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
  }
}

#==============================================================================
# ACTIVE-ACTIVE CONFIGURATION
#==============================================================================

variable "enable_active_active" {
  description = "Enable Active-Active (multi-region) deployment. Forces ingress to be enabled."
  type        = bool
  default     = false
}

#==============================================================================
# RESOURCE TAGGING
#==============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
