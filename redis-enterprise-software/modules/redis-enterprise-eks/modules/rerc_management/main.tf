#==============================================================================
# REDIS ENTERPRISE REMOTE CLUSTER (RERC) MANAGEMENT
#==============================================================================
# This module creates RedisEnterpriseRemoteCluster resources for Active-Active
# database replication across regions.
#
# Key Requirements:
# - apiFqdnUrl must use Route53 FQDN (not NLB hostname) for SSL Passthrough
# - dbFqdnSuffix must use Route53 FQDN suffix for cross-region DB access
#==============================================================================

#==============================================================================
# LOCAL RERC (Points to the local cluster)
#==============================================================================

resource "kubectl_manifest" "local_rerc" {
  count = var.create_local_rerc ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1alpha1
    kind: RedisEnterpriseRemoteCluster
    metadata:
      name: ${var.local_cluster_name}
      namespace: ${var.namespace}
    spec:
      recName: ${var.local_cluster_name}
      recNamespace: ${var.namespace}
      apiFqdnUrl: ${var.local_api_fqdn}
      dbFqdnSuffix: ${var.local_db_fqdn_suffix}
      secretName: redis-enterprise-${var.local_cluster_name}
  YAML

  depends_on = [var.cluster_ready]
}

#==============================================================================
# REMOTE RERC (Points to the remote cluster in another region)
#==============================================================================

resource "kubectl_manifest" "remote_rerc" {
  count = var.create_remote_rerc ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1alpha1
    kind: RedisEnterpriseRemoteCluster
    metadata:
      name: ${var.remote_cluster_name}
      namespace: ${var.namespace}
    spec:
      recName: ${var.remote_cluster_name}
      recNamespace: ${var.namespace}
      apiFqdnUrl: ${var.remote_api_fqdn}
      dbFqdnSuffix: ${var.remote_db_fqdn_suffix}
      secretName: redis-enterprise-${var.remote_cluster_name}
  YAML

  depends_on = [var.cluster_ready]
}

#==============================================================================
# WAIT FOR RERCs TO BE READY
#==============================================================================

resource "time_sleep" "wait_for_rercs" {
  count = (var.create_local_rerc || var.create_remote_rerc) ? 1 : 0

  depends_on = [
    kubectl_manifest.local_rerc,
    kubectl_manifest.remote_rerc
  ]

  create_duration = "30s" # Wait for RERCs to reconcile
}

