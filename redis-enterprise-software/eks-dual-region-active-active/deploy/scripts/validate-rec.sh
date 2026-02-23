#!/bin/bash
# Validate Redis Enterprise Cluster (REC) deployment and configuration
# Usage: ./validate-rec.sh <values-file>

set -e

VALUES_FILE=$1

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file>"
  exit 1
fi

if [ ! -f "$VALUES_FILE" ]; then
  echo "ERROR: Values file not found: $VALUES_FILE"
  exit 1
fi

# Load configuration
if ! command -v yq &> /dev/null; then
  echo "ERROR: yq is required but not installed."
  exit 1
fi

K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REC_NAME=$(yq eval '.rec.name' "$VALUES_FILE")
CLUSTER_NAME=$(yq eval '.cluster.name' "$VALUES_FILE")

echo "=========================================="
echo "REC Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "REC Name: $REC_NAME"
echo ""

# 1. Check REC exists
echo "=== Step 1: Checking REC exists ==="
if ! kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: REC '$REC_NAME' not found"
  exit 1
fi
echo "✓ REC exists"
echo ""

# 2. Check REC status
echo "=== Step 2: Checking REC status ==="
REC_STATE=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.status.state}')
if [ "$REC_STATE" != "Running" ]; then
  echo "✗ ERROR: REC is not Running (current state: $REC_STATE)"
  kubectl describe rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" | tail -30
  exit 1
fi
echo "✓ REC is Running"
echo ""

# 3. Check ingressOrRouteSpec is configured
echo "=== Step 3: Checking ingressOrRouteSpec configuration ==="
INGRESS_SPEC=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.spec.ingressOrRouteSpec}')
if [ -z "$INGRESS_SPEC" ] || [ "$INGRESS_SPEC" == "null" ]; then
  echo "✗ ERROR: ingressOrRouteSpec is not configured on REC"
  echo "  This is required for Active-Active database ingress creation"
  exit 1
fi
echo "✓ ingressOrRouteSpec is configured"

# Check for required annotations
API_FQDN=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.spec.ingressOrRouteSpec.apiFqdnUrl}')
DB_FQDN=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.spec.ingressOrRouteSpec.dbFqdnSuffix}')
INGRESS_CLASS=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.spec.ingressOrRouteSpec.ingressAnnotations.kubernetes\.io/ingress\.class}')

echo "  - API FQDN: $API_FQDN"
echo "  - DB FQDN Suffix: $DB_FQDN"
echo "  - Ingress Class: $INGRESS_CLASS"

if [ -z "$INGRESS_CLASS" ]; then
  echo "✗ WARNING: kubernetes.io/ingress.class annotation is missing"
  echo "  Database ingress resources may not be created properly"
fi
echo ""

# 4. Check REC pods are running
echo "=== Step 4: Checking REC pods ==="
# Only count StatefulSet pods (not operator or services-rigger)
POD_COUNT=$(kubectl get pods -n "$NAMESPACE" --context="$K8S_CONTEXT" -l app=redis-enterprise,redis.io/cluster="$REC_NAME" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
EXPECTED_PODS=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.spec.nodes}')

if [ "$POD_COUNT" -lt "$EXPECTED_PODS" ]; then
  echo "✗ ERROR: Expected $EXPECTED_PODS pods, but only $POD_COUNT are Running"
  kubectl get pods -n "$NAMESPACE" --context="$K8S_CONTEXT" -l app=redis-enterprise
  exit 1
fi
echo "✓ All $EXPECTED_PODS REC pods are Running (found $POD_COUNT total)"
echo ""

# 5. Check operator is ready
echo "=== Step 5: Checking Redis Enterprise Operator ==="
OPERATOR_READY=$(kubectl get deployment redis-enterprise-operator -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [ "$OPERATOR_READY" != "True" ]; then
  echo "✗ ERROR: Operator is not ready"
  exit 1
fi
echo "✓ Operator is ready"
echo ""

# 6. Check admission controller
echo "=== Step 6: Checking Admission Controller ==="
if ! kubectl get validatingwebhookconfiguration redb-admission --context="$K8S_CONTEXT" &>/dev/null && \
   ! kubectl get validatingwebhookconfiguration redis-enterprise-admission --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ WARNING: ValidatingWebhookConfiguration not found"
  echo "  This may cause issues with database creation"
else
  echo "✓ Admission Controller configured"
fi
echo ""

echo "=========================================="
echo "✓ REC Validation Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""

