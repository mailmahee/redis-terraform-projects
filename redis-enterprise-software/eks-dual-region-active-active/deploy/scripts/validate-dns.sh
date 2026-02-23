#!/bin/bash
# Validate DNS records and resolution
# Usage: ./validate-dns.sh <values-file>

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
DB_FQDN_SUFFIX=$(yq eval '.ingress.dbFqdnSuffix' "$VALUES_FILE")

echo "=========================================="
echo "DNS Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo ""

# Get LoadBalancer address
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -n "$LB_HOSTNAME" ]; then
  LB_ADDRESS="$LB_HOSTNAME"
elif [ -n "$LB_IP" ]; then
  LB_ADDRESS="$LB_IP"
else
  echo "✗ ERROR: Cannot determine LoadBalancer address"
  exit 1
fi

echo "LoadBalancer Address: $LB_ADDRESS"
echo ""

# 1. Check API FQDN resolution
echo "=== Step 1: Checking API FQDN DNS Resolution ==="
echo "Testing: $API_FQDN"

# Test with external DNS (Google DNS)
API_RESOLVED=$(dig @8.8.8.8 +short "$API_FQDN" 2>/dev/null | head -1 || echo "")
if [ -z "$API_RESOLVED" ]; then
  echo "✗ ERROR: API FQDN does not resolve via external DNS (8.8.8.8)"
  echo "  Expected to resolve to: $LB_ADDRESS"
  exit 1
fi
echo "✓ API FQDN resolves to: $API_RESOLVED"

# Verify it resolves to the correct LoadBalancer
if [ "$API_RESOLVED" != "$LB_ADDRESS" ]; then
  # For CNAME records, the resolved value might be the LB hostname
  echo "  Note: Resolved address differs from LoadBalancer address"
  echo "  This is expected for CNAME records"
fi
echo ""

# 2. Test DNS resolution from inside Kubernetes
echo "=== Step 2: Testing DNS Resolution from Inside Kubernetes ==="
echo "Testing from REC pod..."

DNS_TEST=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  nslookup "$API_FQDN" 2>/dev/null | grep -A 2 "Name:" | tail -1 || echo "")

if [ -z "$DNS_TEST" ]; then
  echo "✗ WARNING: DNS resolution failed from inside Kubernetes pod"
  echo "  This may cause issues with cross-region connectivity"
else
  echo "✓ DNS resolves from inside Kubernetes"
  echo "  $DNS_TEST"
fi
echo ""

# 3. Check for database DNS records (if databases exist)
echo "=== Step 3: Checking Database DNS Records ==="

# Get list of databases
DB_LIST=$(kubectl get redb -n "$NAMESPACE" --context="$K8S_CONTEXT" --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -z "$DB_LIST" ]; then
  echo "ℹ No databases found (expected before REAADB creation)"
else
  echo "Found databases, checking DNS records..."
  for DB_NAME in $DB_LIST; do
    DB_FQDN="${DB_NAME}${DB_FQDN_SUFFIX}"
    echo ""
    echo "  Testing: $DB_FQDN"
    
    # Test external DNS
    DB_RESOLVED=$(dig @8.8.8.8 +short "$DB_FQDN" 2>/dev/null | head -1 || echo "")
    if [ -z "$DB_RESOLVED" ]; then
      echo "  ✗ ERROR: Database FQDN does not resolve via external DNS"
      echo "    Expected to resolve to: $LB_ADDRESS"
    else
      echo "  ✓ Resolves to: $DB_RESOLVED"
    fi
    
    # Test from inside Kubernetes
    DB_DNS_TEST=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
      nslookup "$DB_FQDN" 2>/dev/null | grep -A 2 "Name:" | tail -1 || echo "")
    
    if [ -z "$DB_DNS_TEST" ]; then
      echo "  ✗ WARNING: DNS resolution failed from inside Kubernetes pod"
    else
      echo "  ✓ Resolves from inside Kubernetes"
    fi
  done
fi
echo ""

# 4. Test HTTPS connectivity to API
echo "=== Step 4: Testing HTTPS Connectivity to API ==="
echo "Testing: https://$API_FQDN:443"

HTTPS_TEST=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$API_FQDN:443" 2>/dev/null || echo "000")

if [ "$HTTPS_TEST" == "000" ]; then
  echo "✗ ERROR: Cannot connect to API via HTTPS"
  echo "  This will prevent cross-region RERC connectivity"
  exit 1
elif [ "$HTTPS_TEST" == "401" ] || [ "$HTTPS_TEST" == "200" ]; then
  echo "✓ HTTPS connectivity successful (HTTP $HTTPS_TEST)"
else
  echo "⚠ HTTPS returned HTTP $HTTPS_TEST (may be expected)"
fi
echo ""

echo "=========================================="
echo "✓ DNS Validation Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""

