#==============================================================================
# ACTIVE-ACTIVE VALIDATION
#==============================================================================
# Active-Active requires ingress and is incompatible with Redis Flex

locals {
  # Force ingress enabled when Active-Active is enabled
  effective_enable_ingress = var.enable_active_active ? true : var.enable_ingress
}

resource "null_resource" "validate_aa_config" {
  count = var.enable_active_active ? 1 : 0

  lifecycle {
    precondition {
      condition     = !var.enable_redis_flex
      error_message = "Active-Active is incompatible with Redis Flex (Auto Tiering). Set enable_redis_flex=false when using Active-Active."
    }

    precondition {
      condition     = var.api_fqdn_url != "" && var.db_fqdn_suffix != ""
      error_message = "Active-Active requires api_fqdn_url and db_fqdn_suffix to be configured for ingress."
    }
  }
}

#==============================================================================
# REDIS ENTERPRISE CLUSTER CREDENTIALS SECRET
#==============================================================================

resource "kubernetes_secret" "redis_enterprise_admin" {
  metadata {
    name      = var.cluster_name # Must match cluster name exactly for bootstrapper
    namespace = var.namespace
  }

  # Kubernetes secrets with 'data' field are automatically base64 encoded by Terraform
  type = "Opaque"

  data = {
    username = var.admin_username
    password = var.admin_password
  }
}

# Bulletin board configmap required by bootstrapper
resource "kubernetes_config_map" "bulletin_board" {
  metadata {
    name      = "${var.cluster_name}-bulletin-board"
    namespace = var.namespace
  }

  data = {
    BulletinBoard = ""
  }
}

#==============================================================================
# REDIS ENTERPRISE CLUSTER (REC)
#==============================================================================

resource "kubectl_manifest" "redis_enterprise_cluster" {
  yaml_body = <<-YAML
    apiVersion: app.redislabs.com/v1
    kind: RedisEnterpriseCluster
    metadata:
      name: ${var.cluster_name}
      namespace: ${var.namespace}
      ${length(var.ui_service_annotations) > 0 ? "annotations:\n" + join("\n", [for k, v in var.ui_service_annotations : "        ${k}: \"${v}\""]) : ""}
    spec:
      nodes: ${var.node_count}

      # Resource allocation per node
      redisEnterpriseNodeResources:
        limits:
          cpu: "${var.node_cpu_limit}"
          memory: ${var.node_memory_limit}
        requests:
          cpu: "${var.node_cpu_request}"
          memory: ${var.node_memory_request}

      # Persistent storage configuration
      persistentSpec:
        enabled: true
        storageClassName: "${var.storage_class_name}"
        volumeSize: ${var.storage_size}

      # Admin credentials
      username: ${var.admin_username}
      # Secret name matches cluster name, so it will be auto-discovered

      # UI service configuration
      uiServiceType: ${var.ui_service_type}

      # Rack awareness for HA (distributes nodes across AZs)
      rackAwarenessNodeLabel: "topology.kubernetes.io/zone"

      # Additional configuration
      redisEnterpriseImageSpec:
        imagePullPolicy: IfNotPresent
        ${var.redis_enterprise_version_tag != "" ? "versionTag: ${var.redis_enterprise_version_tag}" : ""}

      ${var.license_secret_name != "" ? "# License configuration\n      licenseSecretName: ${var.license_secret_name}" : ""}
%{if var.enable_redis_flex~}

      # Redis Flex (Auto Tiering) configuration for flash storage
      redisOnFlashSpec:
        enabled: true
        bigStoreDriver: ${var.redis_flex_storage_driver}
        storageClassName: "${var.redis_flex_storage_class}"
        flashDiskSize: ${var.redis_flex_flash_disk_size}
%{endif~}
%{if local.effective_enable_ingress~}

      # Ingress/Route configuration for external access (required for Active-Active)
      ingressOrRouteSpec:
        apiFqdnUrl: ${var.api_fqdn_url}
        dbFqdnSuffix: ${var.db_fqdn_suffix}
        method: ${var.ingress_method}
%{if var.ingress_method == "ingress" && length(var.ingress_annotations) > 0~}
        ingressAnnotations:
%{for k, v in var.ingress_annotations~}
          ${k}: "${v}"
%{endfor~}
%{endif~}
%{endif~}
  YAML

  depends_on = [
    kubernetes_secret.redis_enterprise_admin
  ]
}

#==============================================================================
# WAIT FOR CLUSTER TO BE READY
#==============================================================================
# Poll until the REC reaches "Running" state. The admission webhook requires
# the REC to be Running before it will accept RERC or REAADB resources.
# A blind time_sleep is not sufficient — the cluster can take 5-10+ minutes.
#==============================================================================

resource "null_resource" "wait_for_cluster" {
  depends_on = [kubectl_manifest.redis_enterprise_cluster]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      KUBEFILE=$(mktemp)
      trap "rm -f $KUBEFILE" EXIT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name} --kubeconfig $KUBEFILE

      echo "Waiting for REC ${var.cluster_name} to reach Running state..."
      MAX_ATTEMPTS=60
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        STATE=$(kubectl --kubeconfig $KUBEFILE get rec ${var.cluster_name} \
          -n ${var.namespace} \
          -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")
        echo "Attempt $((ATTEMPT+1))/$MAX_ATTEMPTS: REC state = $STATE"
        if [ "$STATE" = "Running" ]; then
          echo "REC ${var.cluster_name} is Running."
          exit 0
        fi
        ATTEMPT=$((ATTEMPT+1))
        sleep 10
      done
      echo "ERROR: REC ${var.cluster_name} did not reach Running state within 10 minutes."
      echo "Check: kubectl get rec ${var.cluster_name} -n ${var.namespace} --kubeconfig $KUBEFILE"
      echo "Logs:  kubectl logs -n ${var.namespace} -l name=redis-enterprise-operator --kubeconfig $KUBEFILE --tail=50"
      exit 1
    EOT
  }

  triggers = {
    cluster_name = var.cluster_name
  }
}

# Kept for any resources that used time_sleep.wait_for_cluster as a depends_on
resource "time_sleep" "wait_for_cluster" {
  depends_on      = [null_resource.wait_for_cluster]
  create_duration = "10s"
}

#==============================================================================
# DISABLE PASSWORD COMPLEXITY POLICY
#==============================================================================
# Redis Enterprise enforces password complexity by default. This disables it
# so simple passwords like "admin" can be used in dev/demo environments.
# Runs after the cluster is up via rladmin on the first REC pod.
#==============================================================================

resource "null_resource" "disable_password_complexity" {
  triggers = {
    cluster_name = var.cluster_name
    namespace    = var.namespace
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      KUBEFILE=$(mktemp)
      trap "rm -f $KUBEFILE" EXIT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name} --kubeconfig $KUBEFILE

      echo "Disabling Redis Enterprise password complexity policy..."
      kubectl --kubeconfig $KUBEFILE exec -n ${var.namespace} ${var.cluster_name}-0 \
        -c redis-enterprise-node -- \
        rladmin cluster config password_complexity disable 2>&1 && \
        echo "Password complexity policy disabled." || \
        echo "Warning: could not disable password complexity (cluster may still be initializing, safe to ignore for now)"
    EOT
  }

  depends_on = [time_sleep.wait_for_cluster]
}

#==============================================================================
# ADMISSION CONTROLLER SETUP
#==============================================================================
# Per Redis docs: https://redis.io/docs/latest/operate/kubernetes/deployment/quick-start/#enable-the-admission-controller
# The admission-tls secret is created during REC initialization (not at operator
# startup), so this must run AFTER the REC is up.
# Steps:
#   1. Poll for admission-tls secret
#   2. Get cert from the secret
#   3. Apply webhook.yaml with the namespace substituted
#   4. Patch the ValidatingWebhookConfiguration caBundle with the cert
#==============================================================================

resource "null_resource" "admission_controller" {
  triggers = {
    cluster_name = var.cluster_name
    namespace    = var.namespace
    aws_region   = var.aws_region
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      KUBEFILE=$(mktemp)
      trap "rm -f $KUBEFILE" EXIT
      aws eks update-kubeconfig --region ${var.aws_region} --name ${var.eks_cluster_name} --kubeconfig $KUBEFILE

      echo "Waiting for admission-tls secret (created during REC initialization)..."
      MAX_ATTEMPTS=30
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        SECRET=$(kubectl --kubeconfig $KUBEFILE get secret admission-tls -n ${var.namespace} --ignore-not-found 2>/dev/null)
        if [ -n "$SECRET" ]; then
          echo "admission-tls secret found."
          break
        fi
        ATTEMPT=$((ATTEMPT+1))
        echo "Attempt $ATTEMPT/$MAX_ATTEMPTS: admission-tls not yet available, waiting 10s..."
        sleep 10
      done
      if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
        echo "ERROR: admission-tls secret not created within 5 minutes. REC may not be running."
        echo "Check REC status: kubectl get rec -n ${var.namespace} --kubeconfig $KUBEFILE"
        exit 1
      fi

      CERT=$(kubectl --kubeconfig $KUBEFILE get secret admission-tls -n ${var.namespace} -o jsonpath='{.data.cert}')

      echo "Applying webhook.yaml..."
      curl -fsSL "https://raw.githubusercontent.com/RedisLabs/redis-enterprise-k8s-docs/${var.operator_version}/admission/webhook.yaml" \
        | sed 's/OPERATOR_NAMESPACE/${var.namespace}/g' \
        | kubectl apply --kubeconfig $KUBEFILE -f - 2>&1 || true

      echo "Patching ValidatingWebhookConfiguration caBundle..."
      kubectl --kubeconfig $KUBEFILE patch ValidatingWebhookConfiguration \
        redis-enterprise-admission \
        --type=json \
        -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"$CERT\"}]" 2>&1

      echo "Admission controller configured successfully."
    EOT
  }

  depends_on = [time_sleep.wait_for_cluster]
}

#==============================================================================
# CLEANUP ON DESTROY (prevents hanging)
#==============================================================================

resource "null_resource" "cleanup_on_destroy" {
  triggers = {
    rec_name         = var.cluster_name
    eks_cluster_name = var.eks_cluster_name
    aws_region       = var.aws_region
    namespace        = var.namespace
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      # Configure kubectl for the EKS cluster
      KUBEFILE=$(mktemp)
      aws eks update-kubeconfig --region ${self.triggers.aws_region} --name ${self.triggers.eks_cluster_name} --kubeconfig $KUBEFILE

      # Delete all REDBs first (databases)
      kubectl delete redb --all -n ${self.triggers.namespace} --ignore-not-found=true --timeout=120s --kubeconfig $KUBEFILE || true

      # Wait for databases to be fully deleted
      sleep 30

      # Delete the REC (cluster)
      kubectl delete rec ${self.triggers.rec_name} -n ${self.triggers.namespace} --ignore-not-found=true --timeout=120s --kubeconfig $KUBEFILE || true

      # Wait for cluster pods to terminate
      sleep 30

      # Force delete any remaining PVCs
      kubectl delete pvc --all -n ${self.triggers.namespace} --ignore-not-found=true --timeout=60s --kubeconfig $KUBEFILE || true

      # Cleanup temp file
      rm -f $KUBEFILE

      echo "Redis Enterprise cleanup completed"
    EOT
    on_failure = continue
  }

  depends_on = [kubectl_manifest.redis_enterprise_cluster]
}
