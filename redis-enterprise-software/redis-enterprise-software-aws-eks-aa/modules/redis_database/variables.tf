variable "create_database" {
  description = "Whether to create the database"
  type        = bool
  default     = true
}

variable "database_name" {
  description = "Name of the Redis database"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the database"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Redis Enterprise cluster"
  type        = string
}

variable "cluster_ready" {
  description = "Dependency to ensure cluster is ready before creating database"
  type        = any
  default     = null
}

variable "memory_size" {
  description = "Memory size for the database (e.g., '100MB', '1GB')"
  type        = string
  default     = "100MB"
}

variable "database_port" {
  description = "Port for the database (10000-19999)"
  type        = number
  default     = 12000
  validation {
    condition     = var.database_port >= 10000 && var.database_port <= 19999
    error_message = "Database port must be between 10000 and 19999."
  }
}

variable "replication" {
  description = "Enable replication for the database"
  type        = bool
  default     = true
}

variable "persistence" {
  description = "Persistence mode: 'disabled', 'aofEveryOneSecond', or 'snapshotEvery6Hour'"
  type        = string
  default     = "aofEverySecond"
  validation {
    condition = contains([
      "disabled",
      "aofEverySecond",
      "aofAlways",
      "snapshotEvery1Hour",
      "snapshotEvery6Hour",
      "snapshotEvery12Hour",
    ], var.persistence)
    error_message = "Persistence must be one of: disabled, aofEverySecond, aofAlways, snapshotEvery1Hour, snapshotEvery6Hour, snapshotEvery12Hour."
  }
}

variable "database_password" {
  description = "Password for the database (optional, leave empty for no password)"
  type        = string
  sensitive   = true
  default     = ""
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

variable "eviction_policy" {
  description = "Eviction policy when memory limit is reached"
  type        = string
  default     = "volatile-lru"
  validation {
    condition = contains([
      "volatile-lru", "allkeys-lru", "volatile-lfu", "allkeys-lfu",
      "volatile-random", "allkeys-random", "volatile-ttl", "noeviction"
    ], var.eviction_policy)
    error_message = "Invalid eviction policy. Must be one of: volatile-lru, allkeys-lru, volatile-lfu, allkeys-lfu, volatile-random, allkeys-random, volatile-ttl, noeviction."
  }
}

#==============================================================================
# SERVICE TYPE (for external access)
#==============================================================================

variable "database_service_type" {
  description = "Service type for database access: ClusterIP (internal) or LoadBalancer (external)"
  type        = string
  default     = "ClusterIP"
  validation {
    condition     = contains(["ClusterIP", "LoadBalancer"], var.database_service_type)
    error_message = "Database service type must be ClusterIP or LoadBalancer."
  }
}

variable "database_service_port" {
  description = "Custom service port for external access (different from internal database port)"
  type        = number
  default     = 0 # 0 means use database_port
}

#==============================================================================
# ADVANCED DATABASE CONFIGURATION
#==============================================================================

variable "shard_count" {
  description = "Number of database shards for horizontal scaling (1 for single shard)"
  type        = number
  default     = 1
  validation {
    condition     = var.shard_count >= 1
    error_message = "Shard count must be at least 1."
  }
}

variable "modules_list" {
  description = "List of Redis modules to enable (e.g., [{name = 'RedisJSON', version = '2.6.6'}])"
  type = list(object({
    name    = string
    version = string
  }))
  default = []
}

variable "redis_version" {
  description = "Redis OSS version (e.g., '7.2', leave empty for cluster default)"
  type        = string
  default     = ""
}

variable "client_authentication_certificates" {
  description = "List of Kubernetes secret names containing client TLS certificates"
  type        = list(string)
  default     = []
}

#==============================================================================
# REDIS FLEX (AUTO TIERING) CONFIGURATION
#==============================================================================

variable "enable_redis_flex" {
  description = "Enable Redis Flex (Auto Tiering) for this database. Requires cluster-level Redis Flex to be enabled."
  type        = bool
  default     = false
}

variable "rof_ram_size" {
  description = "RAM size for Redis Flex database (minimum 10% of memory_size, e.g., '10GB'). Required if enable_redis_flex is true."
  type        = string
  default     = "10GB"
}
