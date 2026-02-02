variable "cluster_name" {
  description = "Name of the Redis Enterprise cluster"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster (for kubectl configuration during destroy)"
  type        = string
}

variable "aws_region" {
  description = "AWS region (for kubectl configuration during destroy)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Redis Enterprise cluster"
  type        = string
}

variable "node_count" {
  description = "Number of Redis Enterprise nodes in the cluster"
  type        = number
  default     = 3
  validation {
    condition     = var.node_count >= 3
    error_message = "Redis Enterprise cluster requires minimum 3 nodes for high availability."
  }
}

variable "admin_username" {
  description = "Admin username for Redis Enterprise cluster"
  type        = string
}

variable "admin_password" {
  description = "Admin password for Redis Enterprise cluster"
  type        = string
  sensitive   = true
}

variable "node_cpu_limit" {
  description = "CPU limit for each Redis Enterprise node"
  type        = string
  default     = "2000m"
}

variable "node_memory_limit" {
  description = "Memory limit for each Redis Enterprise node (e.g., '4Gi', '8Gi')"
  type        = string
  default     = "4Gi"
}

variable "node_cpu_request" {
  description = "CPU request for each Redis Enterprise node"
  type        = string
  default     = "1000m"
}

variable "node_memory_request" {
  description = "Memory request for each Redis Enterprise node"
  type        = string
  default     = "2Gi"
}

variable "storage_class_name" {
  description = "Storage class name for persistent volumes"
  type        = string
}

variable "storage_size" {
  description = "Storage size for each Redis Enterprise node (e.g., '50Gi', '100Gi')"
  type        = string
  default     = "50Gi"
}

variable "ui_service_type" {
  description = "Service type for Redis Enterprise UI access (ClusterIP for internal, LoadBalancer for external)"
  type        = string
  default     = "ClusterIP"
  validation {
    condition     = contains(["ClusterIP", "LoadBalancer"], var.ui_service_type)
    error_message = "UI service type must be ClusterIP or LoadBalancer."
  }
}

variable "ui_service_annotations" {
  description = "Annotations for the UI service (e.g., internal LB annotations)"
  type        = map(string)
  default     = {}
}

variable "redis_enterprise_version_tag" {
  description = "Redis Enterprise image tag (matching the operator version)"
  type        = string
  default     = ""
}


variable "database_service_type" {
  description = "Default service type for database access (ClusterIP for internal, LoadBalancer for external)"
  type        = string
  default     = "ClusterIP"
  validation {
    condition     = contains(["ClusterIP", "LoadBalancer"], var.database_service_type)
    error_message = "Database service type must be ClusterIP or LoadBalancer."
  }
}

variable "license_secret_name" {
  description = "Name of Kubernetes secret containing Redis Enterprise license (optional, leave empty for trial)"
  type        = string
  default     = ""
}

#==============================================================================
# REDIS FLEX (AUTO TIERING) CONFIGURATION
#==============================================================================

variable "enable_redis_flex" {
  description = "Enable Redis Flex (Auto Tiering) for flash storage"
  type        = bool
  default     = false
}

variable "redis_flex_storage_class" {
  description = "Storage class for Redis Flex flash storage (must be local NVMe SSDs)"
  type        = string
  default     = "local-scsi"
}

variable "redis_flex_flash_disk_size" {
  description = "Flash disk size per node for Redis Flex (e.g., '100G')"
  type        = string
  default     = "100G"
}

variable "redis_flex_storage_driver" {
  description = "Storage driver for Redis Flex: 'speedb' or 'rocksdb'"
  type        = string
  default     = "speedb"
}

#==============================================================================
# INGRESS/ROUTE CONFIGURATION (for external access)
#==============================================================================

variable "enable_ingress" {
  description = "Enable ingress/route configuration for external access to cluster and databases"
  type        = bool
  default     = false
}

variable "api_fqdn_url" {
  description = "Fully qualified domain name for Redis Enterprise API (required if enable_ingress is true)"
  type        = string
  default     = ""
}

variable "db_fqdn_suffix" {
  description = "FQDN suffix for database access (required if enable_ingress is true)"
  type        = string
  default     = ""
}

variable "ingress_method" {
  description = "Ingress method: 'ingress' for NGINX/HAProxy or 'openShiftRoute' for OpenShift"
  type        = string
  default     = "ingress"
  validation {
    condition     = contains(["ingress", "openShiftRoute"], var.ingress_method)
    error_message = "Ingress method must be 'ingress' or 'openShiftRoute'."
  }
}

variable "ingress_annotations" {
  description = "Annotations for ingress controller (e.g., for SSL passthrough)"
  type        = map(string)
  default = {
    "nginx.ingress.kubernetes.io/ssl-passthrough" = "true"
  }
}
