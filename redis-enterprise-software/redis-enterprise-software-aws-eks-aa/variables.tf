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
  description = "Redis Enterprise cluster name (shared across all regions)"
  type        = string
  default     = "redis-ent-eks"
}

#==============================================================================
# MULTI-REGION CONFIGURATION
#==============================================================================

variable "regions" {
  description = "Map of region configurations for multi-region Active-Active deployment"
  type = map(object({
    vpc_cidr             = string
    public_subnet_cidrs  = list(string)
    private_subnet_cidrs = list(string)
    availability_zones   = optional(list(string), [])
    key_name             = optional(string, "")
    ssh_key_path         = optional(string, "")
  }))

  validation {
    condition     = length(var.regions) >= 1 && length(var.regions) <= 2
    error_message = "Currently supporting 1-2 regions for Active-Active deployment."
  }
}

#==============================================================================
# DNS CONFIGURATION
#==============================================================================

variable "dns_hosted_zone_id" {
  description = "Route53 hosted zone ID for DNS records (required for Active-Active)"
  type        = string
}

variable "create_dns_records" {
  description = "Whether to create Route53 DNS records. Set to false to use NLB DNS names directly."
  type        = bool
  default     = true
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
  description = "Desired number of worker nodes per region"
  type        = number
  default     = 3
  validation {
    condition     = var.node_desired_size >= 3
    error_message = "Redis Enterprise requires minimum 3 worker nodes for high availability."
  }
}

variable "node_min_size" {
  description = "Minimum number of worker nodes per region"
  type        = number
  default     = 3
  validation {
    condition     = var.node_min_size >= 3
    error_message = "Redis Enterprise requires minimum 3 worker nodes for high availability."
  }
}

variable "node_max_size" {
  description = "Maximum number of worker nodes per region"
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
  description = "Number of Redis Enterprise cluster nodes per region"
  type        = number
  default     = 3
  validation {
    condition     = var.redis_cluster_nodes >= 3
    error_message = "Redis Enterprise cluster requires minimum 3 nodes for high availability."
  }
}

variable "redis_cluster_username" {
  description = "Redis Enterprise cluster admin username (email format)"
  type        = string
  default     = "admin@admin.com"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.redis_cluster_username))
    error_message = "Username must be in email format."
  }
}

variable "redis_cluster_password" {
  description = "Redis Enterprise cluster admin password"
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
# Note: Redis Flex is INCOMPATIBLE with Active-Active
#==============================================================================

variable "enable_redis_flex" {
  description = "Enable Redis Flex (Auto Tiering). WARNING: Incompatible with Active-Active."
  type        = bool
  default     = false
}

variable "redis_flex_storage_class" {
  description = "Storage class for Redis Flex flash storage"
  type        = string
  default     = "local-scsi"
}

variable "redis_flex_flash_disk_size" {
  description = "Flash disk size per node for Redis Flex"
  type        = string
  default     = "100G"
}

variable "redis_flex_storage_driver" {
  description = "Storage driver for Redis Flex: 'speedb' or 'rocksdb'"
  type        = string
  default     = "speedb"
}

#==============================================================================
# REDIS UI AND DATABASE SERVICE CONFIGURATION
#==============================================================================

variable "redis_ui_service_type" {
  description = "Service type for Redis Enterprise UI"
  type        = string
  default     = "ClusterIP"
}

variable "ui_internal_lb_enabled" {
  description = "Expose UI via internal AWS LoadBalancer"
  type        = bool
  default     = false
}

variable "ui_service_annotations" {
  description = "Annotations for UI service"
  type        = map(string)
  default = {
    "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
  }
}

variable "redis_database_service_type" {
  description = "Default service type for databases"
  type        = string
  default     = "ClusterIP"
}

variable "redis_license_secret_name" {
  description = "Name of Kubernetes secret containing Redis Enterprise license"
  type        = string
  default     = ""
}

#==============================================================================
# REDIS INGRESS CONFIGURATION (required for Active-Active)
#==============================================================================

variable "redis_ingress_method" {
  description = "Ingress method: 'ingress' for NGINX/HAProxy or 'openShiftRoute'"
  type        = string
  default     = "ingress"
}

variable "redis_ingress_annotations" {
  description = "Annotations for ingress controller (per Redis docs)"
  type        = map(string)
  default = {
    "kubernetes.io/ingress.class"                 = "nginx"
    "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
  }
}

#==============================================================================
# ACTIVE-ACTIVE DATABASE CONFIGURATION
#==============================================================================

variable "create_aa_database" {
  description = "Create an Active-Active database across all regions"
  type        = bool
  default     = true
}

variable "aa_database_name" {
  description = "Name for the Active-Active database"
  type        = string
  default     = "my-aa-db"
}

variable "aa_database_memory" {
  description = "Memory size for the Active-Active database (e.g., '500MB', '1GB')"
  type        = string
  default     = "500MB"
}

variable "aa_database_shard_count" {
  description = "Number of shards for the Active-Active database"
  type        = number
  default     = 1
}

variable "aa_database_replication" {
  description = "Enable replication for the Active-Active database"
  type        = bool
  default     = true
}

variable "aa_database_password" {
  description = "Password for the Active-Active database (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "aa_database_tls_mode" {
  description = "TLS mode for Active-Active database: 'disabled', 'enabled', or 'replica_ssl'"
  type        = string
  default     = "disabled"
  validation {
    condition     = contains(["disabled", "enabled", "replica_ssl"], var.aa_database_tls_mode)
    error_message = "TLS mode must be one of: disabled, enabled, replica_ssl."
  }
}

variable "aa_database_modules" {
  description = "List of Redis modules to enable on the Active-Active database"
  type = list(object({
    name = string
  }))
  default = []
}

#==============================================================================
# RESOURCE TAGGING
#==============================================================================

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
