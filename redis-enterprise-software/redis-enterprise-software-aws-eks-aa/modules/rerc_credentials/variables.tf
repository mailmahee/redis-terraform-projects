#==============================================================================
# RERC CREDENTIALS MODULE VARIABLES
#==============================================================================

variable "local_namespace" {
  description = "Kubernetes namespace in the local cluster where the secret will be created"
  type        = string
  default     = "redis-enterprise"
}

variable "remote_namespace" {
  description = "Kubernetes namespace in the remote cluster where the REC credentials secret exists"
  type        = string
  default     = "redis-enterprise"
}

variable "remote_rec_name" {
  description = "Name of the Redis Enterprise Cluster (REC) in the remote cluster. The credentials secret is named after the REC."
  type        = string
}

variable "rerc_name" {
  description = "Name for the RERC resource. The secret will be named 'redis-enterprise-<rerc_name>'"
  type        = string
}
