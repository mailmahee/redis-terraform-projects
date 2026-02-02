#==============================================================================
# NLB External Access - Variables
#==============================================================================

variable "namespace" {
  description = "Kubernetes namespace for Redis Enterprise"
  type        = string
}

variable "redis_ui_service_name" {
  description = "Name of the Redis Enterprise UI service"
  type        = string
}

variable "expose_ui" {
  description = "Expose Redis Enterprise UI externally via NLB"
  type        = bool
  default     = false
}

variable "redis_db_services" {
  description = "Map of Redis databases to expose externally (database_name => {port, service_name})"
  type = map(object({
    port         = number
    service_name = string
  }))
  default = {}
}

variable "expose_databases" {
  description = "Expose Redis databases externally via NLB"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to Kubernetes resources"
  type        = map(string)
  default     = {}
}
