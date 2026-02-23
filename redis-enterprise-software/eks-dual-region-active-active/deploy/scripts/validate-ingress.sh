#!/bin/bash
# Validate Ingress resources and load balancers
# Usage: ./validate-ingress.sh <values-file>

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
API_FQDN=$(yq eval '.ingress.apiFqdn' "$VALUES_FILE")

echo "=========================================="
echo "Ingress Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo ""

# 1. Check NGINX Ingress Controller is running
echo "=== Step 1: Checking NGINX Ingress Controller ==="
NGINX_READY=$(kubectl get deployment ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "NotFound")
if [ "$NGINX_READY" != "True" ]; then
  echo "✗ ERROR: NGINX Ingress Controller is not ready"
  exit 1
fi
echo "✓ NGINX Ingress Controller is ready"
echo ""

# 2. Check NGINX LoadBalancer service has external IP
echo "=== Step 2: Checking NGINX LoadBalancer ==="
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$LB_HOSTNAME" ] && [ -z "$LB_IP" ]; then
  echo "✗ ERROR: NGINX LoadBalancer has no external address"
  kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT"
  exit 1
fi

if [ -n "$LB_HOSTNAME" ]; then
  echo "✓ LoadBalancer hostname: $LB_HOSTNAME"
elif [ -n "$LB_IP" ]; then
  echo "✓ LoadBalancer IP: $LB_IP"
fi
echo ""

# 3. Check API ingress exists
echo "=== Step 3: Checking API Ingress ==="
if ! kubectl get ingress "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: API ingress '$REC_NAME' not found"
  echo "  Expected ingress name: $REC_NAME (operator-managed)"
  kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT"
  exit 1
fi
echo "✓ API ingress exists: $REC_NAME"

# Check ingress has proper configuration
INGRESS_CLASS=$(kubectl get ingress "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || echo "")
if [ "$INGRESS_CLASS" != "nginx" ]; then
  echo "✗ WARNING: Ingress class is '$INGRESS_CLASS', expected 'nginx'"
fi

INGRESS_HOST=$(kubectl get ingress "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
echo "  - Host: $INGRESS_HOST"
echo "  - IngressClassName: $INGRESS_CLASS"
echo ""

# 4. List all ingress resources
echo "=== Step 4: All Ingress Resources ==="
kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT"
echo ""

# 5. Check for database ingress resources (if any databases exist)
echo "=== Step 5: Checking for Database Ingress Resources ==="
DB_INGRESS_COUNT=$(kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT" --no-headers 2>/dev/null | grep -v "$REC_NAME" | wc -l | tr -d ' ')
if [ "$DB_INGRESS_COUNT" -eq 0 ]; then
  echo "ℹ No database ingress resources found (expected before REAADB creation)"
else
  echo "✓ Found $DB_INGRESS_COUNT database ingress resource(s)"
  kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT" | grep -v "$REC_NAME" || true
  
  # Validate each database ingress has ingressClassName
  echo ""
  echo "  Validating database ingress resources..."
  for ingress in $(kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT" --no-headers | grep -v "$REC_NAME" | awk '{print $1}'); do
    INGRESS_CLASS=$(kubectl get ingress "$ingress" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
      -o jsonpath='{.spec.ingressClassName}' 2>/dev/null || echo "")
    if [ -z "$INGRESS_CLASS" ]; then
      echo "  ✗ WARNING: Ingress '$ingress' has no ingressClassName"
    else
      echo "  ✓ Ingress '$ingress' has ingressClassName: $INGRESS_CLASS"
    fi
  done
fi
echo ""

echo "=========================================="
echo "✓ Ingress Validation Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  - Verify DNS records point to: ${LB_HOSTNAME:-$LB_IP}"
echo "  - Run: ./validate-dns.sh $VALUES_FILE"
echo ""

