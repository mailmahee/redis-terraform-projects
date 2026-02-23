variable "namespace" {
  description = "Kubernetes namespace for Redis Enterprise"
  type        = string
  default     = "redis-enterprise"
}

variable "operator_version" {
  description = "Version of the Redis Enterprise operator bundle (e.g., 'v8.0.2-2')"
  type        = string
  default     = "v8.0.2-2"
}

variable "cluster_name" {
  description = "EKS cluster name for kubeconfig generation"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
}
