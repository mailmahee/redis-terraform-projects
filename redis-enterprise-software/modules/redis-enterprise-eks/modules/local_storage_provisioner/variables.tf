variable "enable_provisioner" {
  description = "Enable local storage provisioner for Redis Flex NVMe discovery"
  type        = bool
  default     = false
}

variable "cluster_ready" {
  description = "Dependency to ensure EKS cluster is ready before deploying provisioner"
  type        = any
  default     = null
}
