#==============================================================================
# REAADB MODULE VARIABLES
#==============================================================================

variable "create_database" {
  description = "Whether to create the Active-Active database"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Name of the Active-Active database"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the REAADB will be created"
  type        = string
  default     = "redis-enterprise"
}

variable "participating_clusters" {
  description = "List of participating cluster names (from RERC resources)"
  type = list(object({
    name = string
  }))
}

variable "database_secret_name" {
  description = "Name of the Kubernetes secret containing the database password"
  type        = string
  default     = ""
}

variable "database_password" {
  description = "Password for the database (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "memory_size" {
  description = "Memory size for the database (e.g., '500MB', '1GB')"
  type        = string
  default     = "500MB"
}

variable "shard_count" {
  description = "Number of shards for the database"
  type        = number
  default     = 1
}

variable "replication" {
  description = "Enable replication for high availability"
  type        = bool
  default     = true
}

variable "tls_mode" {
  description = "TLS mode: 'disabled', 'enabled', or 'replica_ssl'"
  type        = string
  default     = "disabled"
  validation {
    condition     = contains(["disabled", "enabled", "replica_ssl"], var.tls_mode)
    error_message = "TLS mode must be one of: disabled, enabled, replica_ssl."
  }
}

variable "persistence" {
  description = "Persistence mode: '', 'disabled', 'aofEverySecond', 'aofAlways', 'snapshotEvery1Hour', etc."
  type        = string
  default     = ""
}

variable "modules_list" {
  description = "List of Redis modules to enable on the database"
  type = list(object({
    name = string
  }))
  default = []
}

variable "rerc_dependencies" {
  description = "RERC resources that must be ready before creating the REAADB"
  type        = any
  default     = null
}

variable "eks_cluster_name" {
  description = "Name of the EKS cluster where the REAADB is submitted (for kubectl context in local-exec provisioners)"
  type        = string
}

variable "aws_region" {
  description = "AWS region of the EKS cluster where the REAADB is submitted"
  type        = string
}
