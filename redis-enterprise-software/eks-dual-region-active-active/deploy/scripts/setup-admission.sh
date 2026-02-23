#!/bin/bash
# Setup admission controller and validating webhook
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE=$1

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file>"
  exit 1
fi

echo "Loading configuration..."
K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")

echo "Setting up admission controller for context: $K8S_CONTEXT"

# Check if admission-tls secret exists
if ! kubectl get secret admission-tls -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "ERROR: admission-tls secret not found"
  echo "This should have been created by the Redis Enterprise Operator"
  echo "Please check the operator logs"
  exit 1
fi

echo "✓ admission-tls secret exists"

# Get the CA bundle from the secret
CA_BUNDLE=$(kubectl get secret admission-tls -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.data.cert}')

if [ -z "$CA_BUNDLE" ]; then
  echo "ERROR: Could not extract CA bundle from admission-tls secret"
  exit 1
fi

echo "✓ Extracted CA bundle"

# Create ValidatingWebhookConfiguration
cat <<EOF | kubectl apply --context="$K8S_CONTEXT" -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: redis-enterprise-admission
webhooks:
- name: redb.admission.redislabs
  admissionReviewVersions: ["v1beta1"]
  clientConfig:
    service:
      namespace: $NAMESPACE
      name: admission
      path: /admission
    caBundle: $CA_BUNDLE
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["app.redislabs.com"]
    apiVersions: ["v1", "v1alpha1"]
    resources: ["redisenterprisedatabases"]
  failurePolicy: Fail
  sideEffects: None
- name: reaadb.admission.redislabs
  admissionReviewVersions: ["v1beta1"]
  clientConfig:
    service:
      namespace: $NAMESPACE
      name: admission
      path: /admission
    caBundle: $CA_BUNDLE
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["app.redislabs.com"]
    apiVersions: ["v1alpha1"]
    resources: ["redisenterpriseactiveactivedatabases"]
  failurePolicy: Fail
  sideEffects: None
EOF

echo "✓ ValidatingWebhookConfiguration created"

# Wait for admission service to be ready
echo "Waiting for admission service to be ready..."
kubectl wait --for=condition=Available \
  deployment/redis-enterprise-operator \
  -n "$NAMESPACE" \
  --timeout=300s \
  --context="$K8S_CONTEXT"

echo "✓ Admission controller is ready"

