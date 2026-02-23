terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source                = "hashicorp/kubernetes"
      version               = "~> 2.23"
      configuration_aliases = [kubernetes.local, kubernetes.remote]
    }
  }
}
