#==============================================================================
# RERC MODULE VARIABLES
#==============================================================================

variable "rerc_name" {
  description = "Name for the RERC resource (typically: rerc-<remote-region>)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where the RERC will be created"
  type        = string
  default     = "redis-enterprise"
}

variable "local_rec_name" {
  description = "Name of the local RedisEnterpriseCluster (REC) that will participate in Active-Active"
  type        = string
}

variable "remote_api_fqdn" {
  description = "API FQDN of the remote Redis Enterprise cluster"
  type        = string
}

variable "remote_db_fqdn_suffix" {
  description = "Database FQDN suffix of the remote cluster"
  type        = string
}

variable "remote_secret_name" {
  description = "Name of the Kubernetes secret containing the remote cluster's admission-tls certificate"
  type        = string
}

variable "eks_cluster_name" {
  description = "Name of the local EKS cluster (for kubectl context in local-exec provisioners)"
  type        = string
}

variable "aws_region" {
  description = "AWS region of the local EKS cluster (for kubectl context in local-exec provisioners)"
  type        = string
}
