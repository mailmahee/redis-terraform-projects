#==============================================================================
# RERC CREDENTIALS MODULE
#==============================================================================
# Extracts admin credentials from a remote Redis Enterprise cluster and creates
# a secret in the local cluster for RERC (RedisEnterpriseRemoteCluster) to use.
#
# According to Redis docs, RERC requires a secret with username/password fields
# containing the admin credentials of the remote cluster.
# https://redis.io/docs/latest/operate/kubernetes/active-active/prepare-clusters/
#==============================================================================

#==============================================================================
# EXTRACT ADMIN CREDENTIALS FROM REMOTE CLUSTER
#==============================================================================
# The REC credentials secret is named after the cluster and contains username
# and password for the Redis Enterprise admin user.

data "kubernetes_secret" "remote_rec_credentials" {
  provider = kubernetes.remote

  metadata {
    name      = var.remote_rec_name
    namespace = var.remote_namespace
  }
}

#==============================================================================
# CREATE SECRET IN LOCAL CLUSTER FOR RERC
#==============================================================================
# Create a secret in the local cluster containing the remote cluster's admin
# credentials. RERC will use this to authenticate with the remote cluster.

resource "kubernetes_secret" "rerc_credentials" {
  provider = kubernetes.local

  metadata {
    name      = "redis-enterprise-${var.rerc_name}"
    namespace = var.local_namespace
  }

  type = "Opaque"

  data = {
    username = data.kubernetes_secret.remote_rec_credentials.data["username"]
    password = data.kubernetes_secret.remote_rec_credentials.data["password"]
  }
}
