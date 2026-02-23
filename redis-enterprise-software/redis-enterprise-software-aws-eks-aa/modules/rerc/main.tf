#==============================================================================
# REDIS ENTERPRISE REMOTE CLUSTER (RERC) MODULE
#==============================================================================
# Creates a RedisEnterpriseRemoteCluster (RERC) CRD resource that references
# a Redis Enterprise cluster in another region for Active-Active database
# participation.
#
# The RERC resource tells the local operator how to connect to the remote
# cluster, including its API endpoint and TLS certificate.
#==============================================================================

resource "kubectl_manifest" "rerc" {
  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1alpha1
    kind: RedisEnterpriseRemoteCluster
    metadata:
      name: ${var.rerc_name}
      namespace: ${var.namespace}
    spec:
      recName: ${var.local_rec_name}
      recNamespace: ${var.namespace}
      apiFqdnUrl: ${var.remote_api_fqdn}
      dbFqdnSuffix: ${var.remote_db_fqdn_suffix}
      secretName: ${var.remote_secret_name}
  YAML
}

#==============================================================================
# CLEANUP FINALIZERS ON DESTROY
#==============================================================================

resource "null_resource" "cleanup_on_destroy" {
  triggers = {
    rerc_name        = var.rerc_name
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
      kubectl --kubeconfig "$KUBECONFIG_FILE" patch rerc ${self.triggers.rerc_name} -n ${self.triggers.namespace} --type='json' -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
    EOF
  }
}

#==============================================================================
# WAIT FOR RERC TO BE READY (Active Status)
#==============================================================================
# The RERC needs time for:
# 1. The nginx ingress to pick up the ingress resource
# 2. DNS propagation
# 3. The operator to verify connectivity to the remote cluster
# 4. The RERC status to transition from "Pending" to "Active"
#
# We use a longer initial wait, then poll for Active status.
#==============================================================================

resource "time_sleep" "initial_wait_for_rerc" {
  depends_on = [kubectl_manifest.rerc]

  # Initial wait to allow ingress controller to pick up the ingress
  # and for DNS to propagate
  create_duration = "60s"
}

# Poll for RERC to become Active
resource "null_resource" "wait_for_rerc_active" {
  depends_on = [time_sleep.initial_wait_for_rerc]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOF
      KUBECONFIG_FILE=$(mktemp)
      trap "rm -f $KUBECONFIG_FILE" EXIT

      echo "Configuring kubectl for EKS cluster ${var.eks_cluster_name} in ${var.aws_region}..."
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name} --kubeconfig "$KUBECONFIG_FILE" 2>&1

      echo "Waiting for RERC ${var.rerc_name} to become Active..."
      MAX_ATTEMPTS=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        STATUS=$(kubectl --kubeconfig "$KUBECONFIG_FILE" get rerc ${var.rerc_name} -n ${var.namespace} -o jsonpath='{.status.status}' 2>/dev/null || echo "NotFound")
        echo "Attempt $((ATTEMPT+1))/$MAX_ATTEMPTS: RERC ${var.rerc_name} status: $STATUS"
        if [ "$STATUS" = "Active" ]; then
          echo "RERC ${var.rerc_name} is Active!"
          exit 0
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 10
      done
      echo "ERROR: RERC ${var.rerc_name} did not become Active within timeout (5 minutes). Current status: $STATUS"
      echo "Troubleshooting:"
      echo "  1. Check DNS resolution: nslookup ${var.remote_api_fqdn}"
      echo "  2. Check RERC details: kubectl --kubeconfig $KUBECONFIG_FILE describe rerc ${var.rerc_name} -n ${var.namespace}"
      echo "  3. Check operator logs: kubectl --kubeconfig $KUBECONFIG_FILE logs -n ${var.namespace} -l app=redis-enterprise-operator --tail=50"
      echo "  4. Verify VPC peering and security groups allow cross-region traffic"
      exit 1
    EOF
  }

  triggers = {
    rerc_name = var.rerc_name
  }
}
