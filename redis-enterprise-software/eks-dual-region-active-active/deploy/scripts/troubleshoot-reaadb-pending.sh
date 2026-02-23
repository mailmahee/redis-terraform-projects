#!/bin/bash
# REAADB Pending State Troubleshooting Script
# Diagnoses why REAADB stays in pending state
# Based on official Redis Enterprise troubleshooting guidance

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <values-file> [step]"
  echo ""
  echo "Available steps:"
  echo "  1 - Validate RERCs on both sides"
  echo "  2 - Test 9443 and 443 connectivity like the operator"
  echo "  3 - Check LB + NAT hairpin configuration"
  echo "  4 - Sanity-check REAADB creation semantics"
  echo "  5 - Inspect why REAADB is pending"
  echo "  all - Run all steps"
  echo "  collect - Collect diagnostic output for support"
  echo ""
  echo "If no step is specified, shows interactive menu"
  exit 1
fi

VALUES_FILE=$1
STEP=$2

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
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE")
API_FQDN=$(yq eval '.ingress.apiFqdn' "$VALUES_FILE")

# Get remote cluster info (assumes values-region1.yaml has corresponding values-region2.yaml)
if [[ "$VALUES_FILE" == *"region1"* ]]; then
  REMOTE_VALUES_FILE="${VALUES_FILE/region1/region2}"
elif [[ "$VALUES_FILE" == *"region2"* ]]; then
  REMOTE_VALUES_FILE="${VALUES_FILE/region2/region1}"
else
  REMOTE_VALUES_FILE=""
fi

if [ -n "$REMOTE_VALUES_FILE" ] && [ -f "$REMOTE_VALUES_FILE" ]; then
  REMOTE_K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$REMOTE_VALUES_FILE")
  REMOTE_NAMESPACE=$(yq eval '.rec.namespace' "$REMOTE_VALUES_FILE")
  REMOTE_CLUSTER_NAME=$(yq eval '.cluster.name' "$REMOTE_VALUES_FILE")
  REMOTE_API_FQDN=$(yq eval '.ingress.apiFqdn' "$REMOTE_VALUES_FILE")
else
  REMOTE_K8S_CONTEXT=""
  REMOTE_NAMESPACE=""
  REMOTE_CLUSTER_NAME=""
  REMOTE_API_FQDN=""
fi

echo "=========================================="
echo "REAADB Pending Troubleshooting"
echo "=========================================="
echo "Local Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "Namespace: $NAMESPACE"
echo "REAADB: $REAADB_NAME"
echo "API FQDN: $API_FQDN"
if [ -n "$REMOTE_CLUSTER_NAME" ]; then
  echo ""
  echo "Remote Cluster: $REMOTE_CLUSTER_NAME"
  echo "Remote Context: $REMOTE_K8S_CONTEXT"
  echo "Remote API FQDN: $REMOTE_API_FQDN"
fi
echo ""

# Step 1: Validate RERCs on both sides
step_1() {
  echo "=========================================="
  echo "Step 1: Validate RERCs on Both Sides"
  echo "=========================================="
  echo ""

  echo "=== Local Cluster ($CLUSTER_NAME) RERCs ==="
  kubectl get rerc -n "$NAMESPACE" --context="$K8S_CONTEXT"
  echo ""

  echo "=== Local RERC Details ==="
  LOCAL_RERCS=$(kubectl get rerc -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.items[*].metadata.name}')
  for rerc in $LOCAL_RERCS; do
    echo "--- RERC: $rerc ---"
    kubectl describe rerc "$rerc" -n "$NAMESPACE" --context="$K8S_CONTEXT"
    echo ""
  done

  if [ -n "$REMOTE_K8S_CONTEXT" ]; then
    echo "=== Remote Cluster ($REMOTE_CLUSTER_NAME) RERCs ==="
    kubectl get rerc -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT"
    echo ""

    echo "=== Remote RERC Details ==="
    REMOTE_RERCS=$(kubectl get rerc -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT" -o jsonpath='{.items[*].metadata.name}')
    for rerc in $REMOTE_RERCS; do
      echo "--- RERC: $rerc ---"
      kubectl describe rerc "$rerc" -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT"
      echo ""
    done
  fi

  echo "✅ Healthy RERC should show:"
  echo "   - Status: Active"
  echo "   - Spec Status: Valid"
  echo ""
  echo "❌ If Status is anything else, check Events section and operator logs"
  echo ""
  echo "Also verify:"
  echo "   - spec.recName + spec.recNamespace match the local REC"
  echo "   - Secret redis-enterprise-<rerc-name> contains correct admin credentials"
  echo ""
}

# Step 2: Test 9443 and 443 connectivity
step_2() {
  echo "=========================================="
  echo "Step 2: Test 9443 and 443 Like Operator"
  echo "=========================================="
  echo ""

  echo "The operator does HTTPS calls to:"
  echo "  - https://<api-fqdn>/v1/nodes/1 (via LB:443)"
  echo "  - https://<rec-service>:9443/v1/... (inside cluster)"
  echo ""

  echo "=== Test 1: From operator pod to remote API FQDN (port 443) ==="
  if [ -n "$REMOTE_API_FQDN" ]; then
    echo "Testing: https://$REMOTE_API_FQDN/v1/nodes/1"
    kubectl exec -n "$NAMESPACE" deploy/redis-enterprise-operator --context="$K8S_CONTEXT" -- \
      curl -vk "https://$REMOTE_API_FQDN/v1/nodes/1" 2>&1 || true
  else
    echo "Remote API FQDN not available - manual test required:"
    echo "  kubectl exec -n $NAMESPACE deploy/redis-enterprise-operator --context=$K8S_CONTEXT -- \\"
    echo "    curl -vk https://<remote-api-fqdn>/v1/nodes/1"
  fi
  echo ""


  echo "If 9443 direct works but 443 FQDN fails → LB/firewall/NAT issue"
  echo "If both fail → fix REC networking first"
  echo ""
}

# Step 3: Check LB + NAT hairpin
step_3() {
  echo "=========================================="
  echo "Step 3: Check LB + NAT Hairpin Config"
  echo "=========================================="
  echo ""

  echo "The RERC controller connects to REC via external address (API FQDN/LB)"
  echo "Redis requires that the LB supports NAT hairpinning for this to work"
  echo ""

  echo "=== DNS Resolution Test ==="
  echo "Testing DNS for: $API_FQDN"
  kubectl exec -n "$NAMESPACE" deploy/redis-enterprise-operator --context="$K8S_CONTEXT" -- \
    nslookup "$API_FQDN" 2>&1 || echo "DNS lookup failed"
  echo ""

  echo "=== Load Balancer Services ==="
  kubectl get svc -n "$NAMESPACE" --context="$K8S_CONTEXT" | grep -E "NAME|LoadBalancer"
  echo ""

  echo "=== Ingress Resources ==="
  kubectl get ingress -n "$NAMESPACE" --context="$K8S_CONTEXT"
  echo ""

  echo "Requirements:"
  echo "  ✅ API LB forwards 443 → rec service 9443 on all nodes"
  echo "  ✅ Security groups/firewalls allow 443 between clusters"
  echo "  ✅ Hairpin traffic from inside cluster back to LB is allowed"
  echo "  ✅ DNS for API FQDN resolves from operator pods in all clusters"
  echo ""
  echo "If hairpin isn't possible:"
  echo "  → Point apiFqdnUrl at internal endpoint (internal LB or route)"
  echo ""
}

# Step 4: Sanity-check REAADB creation
step_4() {
  echo "=========================================="
  echo "Step 4: Sanity-Check REAADB Creation"
  echo "=========================================="
  echo ""

  echo "=== REAADB Resource ==="
  kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" 2>/dev/null || echo "REAADB not found in local cluster"
  echo ""

  if [ -n "$REMOTE_K8S_CONTEXT" ]; then
    echo "=== Remote REAADB Resource ==="
    kubectl get reaadb "$REAADB_NAME" -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT" 2>/dev/null || echo "REAADB not found in remote cluster (expected if only applied to one side)"
    echo ""
  fi

  echo "Checklist:"
  echo "  ✅ RERC YAMLs: applied on BOTH clusters (each knows about the other)"
  echo "  ✅ REAADB YAML: applied on ONE cluster only (operator propagates to peer)"
  echo "  ✅ Use one shared namespace per cluster (REC, RERC, REAADB all there)"
  echo "  ✅ Cluster names + namespaces are unique per cluster (not identical)"
  echo ""
  echo "Avoid in early troubleshooting:"
  echo "  ❌ REAADB in different namespace than REC/RERC (known edge-cases)"
  echo "  ❌ Identical cluster names on both sides"
  echo ""
}

# Step 5: Inspect why REAADB is pending
step_5() {
  echo "=========================================="
  echo "Step 5: Inspect Why REAADB is Pending"
  echo "=========================================="
  echo ""

  echo "=== REAADB Description ==="
  kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" 2>/dev/null || echo "REAADB not found"
  echo ""

  echo "Look for:"
  echo "  - Status: and Spec Status:"
  echo "  - Events (usually show 'failed to observe active-active database state')"
  echo ""

  echo "=== Operator Logs (filtered for REAADB) ==="
  kubectl logs deploy/redis-enterprise-operator -n "$NAMESPACE" --context="$K8S_CONTEXT" --tail=100 | grep -i reaadb -A3 -B3 || echo "No REAADB-related logs found"
  echo ""

  echo "Common patterns when connectivity is broken:"
  echo "  ❌ Failed executing HTTP request ... Get \"https://<api-fqdn>/v1/nodes/1\": read ...:443: read: connection reset by peer"
  echo "  ❌ could not get existing active-active database from RedisEnterpriseCluster ... /v1/crdbs/<guid> ... read: connection reset by peer"
  echo ""
  echo "Once 9443/443 and RERC status are clean, REAADB usually transitions pending → active"
  echo ""
}

# Collect diagnostic output
collect_diagnostics() {
  echo "=========================================="
  echo "Collecting Diagnostic Output"
  echo "=========================================="
  echo ""

  OUTPUT_DIR="reaadb-diagnostics-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$OUTPUT_DIR"

  echo "Collecting to: $OUTPUT_DIR/"
  echo ""

  # Local cluster diagnostics
  echo "Collecting local cluster diagnostics..."
  kubectl describe rerc -n "$NAMESPACE" --context="$K8S_CONTEXT" > "$OUTPUT_DIR/local-rerc-describe.txt" 2>&1
  kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" > "$OUTPUT_DIR/local-reaadb-describe.txt" 2>&1
  kubectl logs deploy/redis-enterprise-operator -n "$NAMESPACE" --context="$K8S_CONTEXT" --tail=200 > "$OUTPUT_DIR/local-operator-logs.txt" 2>&1

  # Test API connectivity
  echo "Testing API connectivity..."
  if [ -n "$REMOTE_API_FQDN" ]; then
    kubectl exec -n "$NAMESPACE" deploy/redis-enterprise-operator --context="$K8S_CONTEXT" -- \
      curl -vk "https://$REMOTE_API_FQDN/v1/nodes/1" > "$OUTPUT_DIR/local-curl-remote-api.txt" 2>&1 || true
  fi

  # Remote cluster diagnostics
  if [ -n "$REMOTE_K8S_CONTEXT" ]; then
    echo "Collecting remote cluster diagnostics..."
    kubectl describe rerc -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT" > "$OUTPUT_DIR/remote-rerc-describe.txt" 2>&1
    kubectl logs deploy/redis-enterprise-operator -n "$REMOTE_NAMESPACE" --context="$REMOTE_K8S_CONTEXT" --tail=200 > "$OUTPUT_DIR/remote-operator-logs.txt" 2>&1

    kubectl exec -n "$REMOTE_NAMESPACE" deploy/redis-enterprise-operator --context="$REMOTE_K8S_CONTEXT" -- \
      curl -vk "https://$API_FQDN/v1/nodes/1" > "$OUTPUT_DIR/remote-curl-local-api.txt" 2>&1 || true
  fi

  echo ""
  echo "✅ Diagnostics collected in: $OUTPUT_DIR/"
  echo ""
  echo "Files collected:"
  ls -lh "$OUTPUT_DIR/"
  echo ""
  echo "Share these files when requesting support."
  echo ""
}

# Run all steps
run_all() {
  step_1
  read -p "Press Enter to continue to Step 2..."
  step_2
  read -p "Press Enter to continue to Step 3..."
  step_3
  read -p "Press Enter to continue to Step 4..."
  step_4
  read -p "Press Enter to continue to Step 5..."
  step_5

  echo ""
  echo "=========================================="
  echo "All Steps Complete"
  echo "=========================================="
  echo ""
}

# Interactive menu
show_menu() {
  echo "Select troubleshooting step:"
  echo ""
  echo "  1) Validate RERCs on both sides"
  echo "  2) Test 9443 and 443 connectivity"
  echo "  3) Check LB + NAT hairpin configuration"
  echo "  4) Sanity-check REAADB creation semantics"
  echo "  5) Inspect why REAADB is pending"
  echo "  c) Collect diagnostic output for support"
  echo "  a) Run all steps"
  echo "  q) Quit"
  echo ""
  read -p "Enter choice [1-5,c,a,q]: " choice

  case $choice in
    1) step_1 ;;
    2) step_2 ;;
    3) step_3 ;;
    4) step_4 ;;
    5) step_5 ;;
    c|C) collect_diagnostics ;;
    a|A) run_all ;;
    q|Q) exit 0 ;;
    *) echo "Invalid choice" ;;
  esac
}

# Main execution
case "$STEP" in
  1) step_1 ;;
  2) step_2 ;;
  3) step_3 ;;
  4) step_4 ;;
  5) step_5 ;;
  all) run_all ;;
  collect) collect_diagnostics ;;
  *) show_menu ;;
esac
  echo ""

  echo "=== Test 2: From REC pod to its own 9443 (bypass LB) ==="
  echo "Testing: https://$REC_NAME.$NAMESPACE.svc.cluster.local:9443/v1/nodes/1"
  kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
    curl -vk "https://$REC_NAME.$NAMESPACE.svc.cluster.local:9443/v1/nodes/1" 2>&1 || true
  echo ""

