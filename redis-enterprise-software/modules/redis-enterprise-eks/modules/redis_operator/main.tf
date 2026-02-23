#==============================================================================
# KUBERNETES NAMESPACE FOR REDIS ENTERPRISE
#==============================================================================

resource "kubernetes_namespace" "redis_enterprise" {
  metadata {
    name = var.namespace

    labels = {
      name = var.namespace
    }
  }
}

#==============================================================================
# REDIS ENTERPRISE OPERATOR (via Bundle)
#==============================================================================

# Apply the operator bundle directly via kubectl
resource "null_resource" "redis_enterprise_operator" {
  triggers = {
    operator_version = var.operator_version
    namespace        = kubernetes_namespace.redis_enterprise.metadata[0].name
    cluster_name     = var.cluster_name
    aws_region       = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      KUBEFILE=$(mktemp)
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name} --kubeconfig $KUBEFILE --alias ${var.cluster_name}
      kubectl apply -n ${kubernetes_namespace.redis_enterprise.metadata[0].name} \
        -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/${var.operator_version}/bundle.yaml \
        --validate=false \
        --kubeconfig $KUBEFILE
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = <<-EOT
      KUBEFILE=$(mktemp)
      aws eks update-kubeconfig --region ${self.triggers.aws_region} --name ${self.triggers.cluster_name} --kubeconfig $KUBEFILE --alias ${self.triggers.cluster_name}

      echo "=========================================="
      echo "Deleting Redis Enterprise resources in correct order..."
      echo "=========================================="

      # Delete resources in CORRECT ORDER (resources before CRDs)
      # This prevents slow cascade deletion and finalizer hangs

      echo "Step 1: Deleting Active-Active Databases (REAADB)..."
      kubectl delete reaadb --all -n ${self.triggers.namespace} --timeout=60s --kubeconfig $KUBEFILE || true

      echo "Step 2: Deleting Remote Cluster resources (RERC)..."
      kubectl delete rerc --all -n ${self.triggers.namespace} --timeout=60s --kubeconfig $KUBEFILE || true

      echo "Step 3: Deleting Database resources (REDB)..."
      kubectl delete redb --all -n ${self.triggers.namespace} --timeout=60s --kubeconfig $KUBEFILE || true

      echo "Step 4: Deleting Redis Enterprise Cluster (REC)..."
      kubectl delete rec --all -n ${self.triggers.namespace} --timeout=120s --kubeconfig $KUBEFILE || true

      echo "Step 5: Waiting for Redis Enterprise pods to terminate..."
      kubectl wait --for=delete pod -l app=redis-enterprise -n ${self.triggers.namespace} \
        --timeout=120s --kubeconfig $KUBEFILE || true

      # NOW delete CRDs (will be fast since all resource instances are gone)
      echo "Step 6: Deleting CRDs..."
      kubectl delete -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/${self.triggers.operator_version}/bundle.yaml \
        --ignore-not-found=true --kubeconfig $KUBEFILE || true

      # Finally delete namespace (will be instant since it's empty)
      echo "Step 7: Deleting namespace..."
      kubectl delete namespace ${self.triggers.namespace} --timeout=60s --kubeconfig $KUBEFILE || true

      echo "=========================================="
      echo "Redis Enterprise cleanup complete!"
      echo "=========================================="
    EOT
  }

  depends_on = [kubernetes_namespace.redis_enterprise]
}

# ClusterRole and Binding for operator to list/watch nodes
resource "kubernetes_cluster_role" "redis_enterprise_operator_nodes" {
  metadata {
    name = "${kubernetes_namespace.redis_enterprise.metadata[0].name}-operator-nodes"
  }

  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "redis_enterprise_operator_nodes" {
  metadata {
    name = "${kubernetes_namespace.redis_enterprise.metadata[0].name}-operator-nodes"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.redis_enterprise_operator_nodes.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "redis-enterprise-operator"
    namespace = kubernetes_namespace.redis_enterprise.metadata[0].name
  }
}

#==============================================================================
# WAIT FOR OPERATOR TO BE READY
#==============================================================================

# This ensures the operator CRDs are fully installed before proceeding
resource "time_sleep" "wait_for_operator" {
  depends_on = [null_resource.redis_enterprise_operator]

  create_duration = "60s" # Increased for bundle deployment
}
