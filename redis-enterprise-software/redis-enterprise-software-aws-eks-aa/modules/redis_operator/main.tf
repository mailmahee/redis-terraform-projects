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
      # Delete CRDs cluster-scoped; ignore namespace flag
      kubectl delete -f https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/${self.triggers.operator_version}/bundle.yaml \
        --ignore-not-found=true --kubeconfig $KUBEFILE
      # Best-effort delete namespace-scoped objects
      kubectl delete namespace ${self.triggers.namespace} --ignore-not-found=true --kubeconfig $KUBEFILE
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
