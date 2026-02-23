#==============================================================================
# REDIS ENTERPRISE ACTIVE-ACTIVE DATABASE (REAADB) MODULE
#==============================================================================
# Creates a RedisEnterpriseActiveActiveDatabase (REAADB) CRD resource.
# This is the central configuration for an Active-Active database that
# spans multiple Redis Enterprise clusters.
#
# The REAADB is created in one cluster (typically region1) and the Redis
# Enterprise operator syncs the configuration to all participating clusters
# via the RERC connections.
#==============================================================================

resource "kubectl_manifest" "reaadb" {
  count = var.create_database ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1alpha1
    kind: RedisEnterpriseActiveActiveDatabase
    metadata:
      name: ${var.database_name}
      namespace: ${var.namespace}
    spec:
      participatingClusters:
%{for cluster in var.participating_clusters~}
        - name: ${cluster.name}
%{endfor~}
      globalConfigurations:
%{if var.database_secret_name != ""~}
        databaseSecretName: ${var.database_secret_name}
%{endif~}
        memorySize: ${var.memory_size}
        shardCount: ${var.shard_count}
        replication: ${var.replication}
%{if var.tls_mode != "disabled"~}
        tlsMode: ${var.tls_mode}
%{endif~}
%{if var.persistence != ""~}
        persistence: ${var.persistence}
%{endif~}
%{if length(var.modules_list) > 0~}
        modulesList:
%{for m in var.modules_list~}
          - name: ${m.name}
%{endfor~}
%{endif~}
  YAML

  depends_on = [
    var.rerc_dependencies,
    kubernetes_secret.database_password,
  ]
}

#==============================================================================
# DATABASE SECRET (optional - for password authentication)
#==============================================================================

resource "kubernetes_secret" "database_password" {
  count = var.create_database && var.database_password != "" ? 1 : 0

  metadata {
    name      = var.database_secret_name
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    password = var.database_password
  }
}

#==============================================================================
# WAIT FOR DATABASE TO BE ACTIVE
#==============================================================================
# Poll for the REAADB to reach "active" status instead of blind waiting.
# The CRDB coordinator needs to provision BDB instances on all participating
# clusters, which requires cross-cluster communication.
#==============================================================================

resource "null_resource" "wait_for_reaadb_active" {
  count = var.create_database ? 1 : 0

  depends_on = [kubectl_manifest.reaadb]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      KUBECONFIG_FILE=$(mktemp)
      trap "rm -f $KUBECONFIG_FILE" EXIT

      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name} --kubeconfig "$KUBECONFIG_FILE" 2>&1

      echo "Waiting for REAADB ${var.database_name} to become active..."
      MAX_ATTEMPTS=60
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        STATUS=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get reaadb ${var.database_name} -n ${var.namespace} -o jsonpath='{.status.status}' 2>/dev/null || echo "NotFound")
        LINKED=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get reaadb ${var.database_name} -n ${var.namespace} -o jsonpath='{.status.linkedRedbs}' 2>/dev/null || echo "")
        REPL=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get reaadb ${var.database_name} -n ${var.namespace} -o jsonpath='{.status.replicationStatus}' 2>/dev/null || echo "")
        echo "Attempt $((ATTEMPT+1))/$MAX_ATTEMPTS: REAADB status=$STATUS linkedRedbs=$LINKED replication=$REPL"
        if [ "$STATUS" = "active" ]; then
          echo "REAADB ${var.database_name} is active!"
          exit 0
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 10
      done
      echo "ERROR: REAADB ${var.database_name} did not become active within 10 minutes. Current status: $STATUS"
      echo "Troubleshooting:"
      echo "  1. Describe REAADB: kubectl describe reaadb ${var.database_name} -n ${var.namespace}"
      REC_POD=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get pods -n ${var.namespace} -l redis.io/role=node -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "unknown")
      echo "  2. Check BDB status: kubectl exec -n ${var.namespace} $REC_POD -c redis-enterprise-node -- curl -sk https://localhost:9443/v1/bdbs -u admin@admin.com"
      echo "  3. Check operator logs: kubectl logs -n ${var.namespace} -l name=redis-enterprise-operator --tail=50"
      exit 1
    EOF
  }
}

#==============================================================================
# CLEANUP FINALIZERS ON DESTROY
#==============================================================================
# Remove finalizers before deletion to prevent circular dependency with REC

resource "null_resource" "cleanup_on_destroy" {
  count = var.create_database ? 1 : 0

  triggers = {
    database_name    = var.database_name
    namespace        = var.namespace
    eks_cluster_name = var.eks_cluster_name
    aws_region       = var.aws_region
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      KUBECONFIG_FILE=$(mktemp)
      trap "rm -f $KUBECONFIG_FILE" EXIT
      aws eks update-kubeconfig --region ${self.triggers.aws_region} --name ${self.triggers.eks_cluster_name} --kubeconfig "$KUBECONFIG_FILE" 2>/dev/null
      kubectl --kubeconfig "$KUBECONFIG_FILE" patch reaadb ${self.triggers.database_name} -n ${self.triggers.namespace} --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
    EOF
  }
}
