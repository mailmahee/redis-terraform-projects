#==============================================================================
# LOCAL STORAGE PROVISIONER FOR REDIS FLEX
#==============================================================================
# This module deploys the local storage provisioner for NVMe SSD discovery
# Only deployed when enable_provisioner = true (Redis Flex enabled)
#==============================================================================

#==============================================================================
# PARSE MULTI-DOCUMENT YAML FILE
#==============================================================================
# The local-storage-provisioner.yaml contains 7 Kubernetes resources:
# 1. Namespace, 2. ServiceAccount, 3. ClusterRole, 4. ClusterRoleBinding,
# 5. ConfigMap, 6. DaemonSet, 7. StorageClass
#==============================================================================

data "kubectl_path_documents" "local_storage_provisioner" {
  count   = var.enable_provisioner ? 1 : 0
  pattern = "${path.module}/../../k8s-manifests/provisioners/local-storage-provisioner.yaml"
}

#==============================================================================
# APPLY EACH DOCUMENT FROM THE YAML FILE
#==============================================================================
# This properly handles multi-document YAML by applying each resource separately
#==============================================================================

resource "kubectl_manifest" "local_storage_provisioner" {
  count     = var.enable_provisioner ? length(data.kubectl_path_documents.local_storage_provisioner[0].documents) : 0
  yaml_body = element(data.kubectl_path_documents.local_storage_provisioner[0].documents, count.index)

  depends_on = [var.cluster_ready]
}

#==============================================================================
# WAIT FOR PROVISIONER TO DISCOVER NVME DEVICES
#==============================================================================

resource "time_sleep" "wait_for_nvme_discovery" {
  count = var.enable_provisioner ? 1 : 0

  depends_on = [kubectl_manifest.local_storage_provisioner]

  create_duration = "30s" # Wait for DaemonSet to discover and mount NVMe devices
}
