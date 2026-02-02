#==============================================================================
# Redis Test Client - Variables
#==============================================================================

variable "deployment_name" {
  description = "Name of the Kubernetes deployment"
  type        = string
  default     = "redis-test-client"
}

variable "namespace" {
  description = "Kubernetes namespace to deploy the test client"
  type        = string
  default     = "redis-enterprise"
}

variable "redis_host" {
  description = "Redis Enterprise database service hostname"
  type        = string
}

variable "redis_port" {
  description = "Redis Enterprise database port"
  type        = number
  default     = 12000
}

variable "redis_password" {
  description = "Redis database password"
  type        = string
  sensitive   = true
}

# Resource sizing (t3.micro equivalent: 1 vCPU, 1GB RAM)
variable "cpu_request" {
  description = "CPU request (t3.micro = 500m)"
  type        = string
  default     = "500m"
}

variable "cpu_limit" {
  description = "CPU limit (t3.micro = 1000m = 1 vCPU)"
  type        = string
  default     = "1000m"
}

variable "memory_request" {
  description = "Memory request (t3.micro = 512Mi)"
  type        = string
  default     = "512Mi"
}

variable "memory_limit" {
  description = "Memory limit (t3.micro = 1Gi = 1GB RAM)"
  type        = string
  default     = "1Gi"
}

variable "create_test_scripts" {
  description = "Create ConfigMap with helper test scripts"
  type        = bool
  default     = true
}

variable "redis_cluster_ready" {
  description = "Dependency to ensure Redis cluster is ready before deploying test client"
  type        = any
  default     = null
}
