#!/bin/bash
# CRDB (Active-Active) Troubleshooting Script
# Based on official Redis Enterprise CRDB-on-K8s runbook
# Usage: ./troubleshoot-crdb.sh <values-file> [step]

set -e

VALUES_FILE=$1
STEP=$2

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file> [step]"
  echo ""
  echo "Available steps:"
  echo "  0 - Identify CRDB & participants"
  echo "  1 - Check K8s / operator health"
  echo "  2 - Check REC & DB health from inside pod"
  echo "  3 - Verify CRDB syncer state"
  echo "  4 - Check inter-cluster network"
  echo "  5 - Check TLS / cert issues"
  echo "  6 - End-to-end data-plane connectivity test"
  echo "  all - Run all steps"
  echo ""
  echo "If no step is specified, shows interactive menu"
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
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE")

echo "=========================================="
echo "CRDB Troubleshooting for $CLUSTER_NAME"
echo "=========================================="
echo "Context: $K8S_CONTEXT"
echo "Namespace: $NAMESPACE"
echo "REAADB: $REAADB_NAME"
echo ""

# Function to execute commands in REC pod
exec_rec() {
  kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- "$@"
}

# Step 0: Identify CRDB & participants
step_0() {
  echo "=========================================="
  echo "Step 0: Identify CRDB & Participants"
  echo "=========================================="
  echo ""

  echo "=== Listing all CRDBs ==="
  exec_rec crdb-cli crdb list
  echo ""

  echo "To check specific CRDB status, run:"
  echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- \\"
  echo "    crdb-cli crdb status --crdb-guid <CRDB_GUID>"
  echo ""

  echo "Get CRDB GUID from REAADB:"
  kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.status.replicaSourceStatuses[*].guid}' 2>/dev/null || echo "REAADB not found or no GUID available"
  echo ""
}

# Step 1: Check K8s / operator health
step_1() {
  echo "=========================================="
  echo "Step 1: Check K8s / Operator Health"
  echo "=========================================="
  echo ""

  echo "=== Kubernetes Resources ==="
  kubectl get rec,reaadb,rerc,pods,svc -n "$NAMESPACE" --context="$K8S_CONTEXT"
  echo ""

  echo "=== REAADB Details ==="
  kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" 2>/dev/null || echo "REAADB not found"
  echo ""

  echo "=== Recent Events (last 20) ==="
  kubectl get events -n "$NAMESPACE" --context="$K8S_CONTEXT" --sort-by=.lastTimestamp | tail -20
  echo ""

  echo "=== Operator Logs (last 50 lines) ==="
  kubectl logs deploy/redis-enterprise-operator -n "$NAMESPACE" --context="$K8S_CONTEXT" --tail=50 2>/dev/null || echo "Operator logs not available"
  echo ""

  echo "Look for:"
  echo "  - AA controller errors"
  echo "  - Webhook/TLS issues"
  echo "  - 'connectivity check failed' or 'replication link down' events"
  echo ""
}

# Step 2: Check REC & DB health from inside pod
step_2() {
  echo "=========================================="
  echo "Step 2: Check REC & DB Health"
  echo "=========================================="
  echo ""

  echo "=== Cluster + DB Health (rladmin status extra all) ==="
  exec_rec rladmin status extra all
  echo ""

  echo "=== Node-level Checks (rlcheck) ==="
  exec_rec rlcheck --continue-on-error
  echo ""

  echo "Verify:"
  echo "  - CRDB DB shows status OK"
  echo "  - All endpoints are up"
  echo "  - No node health issues"
  echo ""
}

# Step 3: Verify CRDB syncer state
step_3() {
  echo "=========================================="
  echo "Step 3: Verify CRDB Syncer State"
  echo "=========================================="
  echo ""

  echo "=== CRDB List ==="
  exec_rec crdb-cli crdb list
  echo ""

  echo "To check CRDB status on this cluster:"
  echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- \\"
  echo "    crdb-cli crdb status --crdb-guid <CRDB_GUID>"
  echo ""

  echo "Expected: All participants show syncing/online, no repeated failures"
  echo ""

  echo "To check CRDT info from database endpoint:"
  echo "  redis-cli -h <db-endpoint> -p <port> info crdt"
  echo ""
}

# Step 4: Check inter-cluster network
step_4() {
  echo "=========================================="
  echo "Step 4: Check Inter-Cluster Network"
  echo "=========================================="
  echo ""

  API_FQDN=$(yq eval '.ingress.apiFqdn' "$VALUES_FILE")

  echo "=== Testing API Ingress ==="
  echo "API FQDN: $API_FQDN"
  echo ""

  echo "From REC pod:"
  exec_rec curl -vk "https://$API_FQDN" 2>&1 | head -20
  echo ""

  echo "=== DNS Resolution Test ==="
  exec_rec nslookup "$API_FQDN" || echo "DNS lookup failed"
  echo ""

  echo "Verify:"
  echo "  - DNS resolution for API + replication hostnames"
  echo "  - Firewall/LB allows AA replication port(s)"
  echo "  - External load balancers have all REC nodes in pool"
  echo "  - No health-check issues on LB"
  echo ""
}

# Step 5: Check TLS / cert issues
step_5() {
  echo "=========================================="
  echo "Step 5: Check TLS / Cert Issues"
  echo "=========================================="
  echo ""

  echo "=== Checking CRDB TLS Configuration ==="
  echo "To verify TLS is enabled for AA cluster connections:"
  echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- \\"
  echo "    crdb-cli crdb status --crdb-guid <CRDB_GUID>"
  echo ""

  echo "=== Certificate Validation ==="
  echo "Check proxy/syncer certs:"
  echo "  - Valid, not expired"
  echo "  - Key size OK"
  echo ""

  echo "If certs were updated, force CRDB to re-bind:"
  echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- \\"
  echo "    crdb-cli crdb update --crdb-guid <CRDB_GUID> --force"
  echo ""

  echo "Common issue: Expired/mismatched syncer certs cause 'replication link is down'"
  echo ""
}

# Step 6: End-to-end data-plane connectivity test
step_6() {
  echo "=========================================="
  echo "Step 6: End-to-End Data-Plane Test"
  echo "=========================================="
  echo ""

  echo "=== Database Service Information ==="
  kubectl get svc -n "$NAMESPACE" --context="$K8S_CONTEXT" | grep -E "NAME|database"
  echo ""

  echo "=== Testing Direct Service (bypass ingress) ==="
  echo "To test direct service access:"
  echo "  kubectl port-forward -n $NAMESPACE svc/<db-svc> 16441:16441 &"
  echo "  redis-cli -h 127.0.0.1 -p 16441 ping"
  echo ""

  echo "=== Testing Through Ingress/LB with TLS + SNI ==="
  echo "To test through ingress:"
  echo "  redis-cli -h <db-hostname> -p 443 --tls --sni <db-hostname> --insecure ping"
  echo ""

  echo "This isolates:"
  echo "  - Service/ClusterIP issues vs ingress/LB issues"
  echo "  - TLS/SNI misconfig vs raw TCP problems"
  echo ""
}

# Run all steps
run_all() {
  step_0
  read -p "Press Enter to continue to Step 1..."
  step_1
  read -p "Press Enter to continue to Step 2..."
  step_2
  read -p "Press Enter to continue to Step 3..."
  step_3
  read -p "Press Enter to continue to Step 4..."
  step_4
  read -p "Press Enter to continue to Step 5..."
  step_5
  read -p "Press Enter to continue to Step 6..."
  step_6

  echo ""
  echo "=========================================="
  echo "All Steps Complete"
  echo "=========================================="
  echo ""
  echo "Summary of CRDB troubleshooting flow:"
  echo "  0. Identify CRDB & participants (crdb-cli crdb list/status)"
  echo "  1. Check K8s resources, events, operator logs"
  echo "  2. Check REC & DB health (rladmin status, rlcheck)"
  echo "  3. Verify CRDB syncer state (crdb-cli crdb status on each REC)"
  echo "  4. Validate inter-REC network (DNS/LB/ports)"
  echo "  5. Validate AA TLS/syncer certs"
  echo "  6. Test data-plane connectivity (redis-cli INFO/CRDT & ping)"
  echo ""
}

# Interactive menu
show_menu() {
  echo "Select troubleshooting step:"
  echo ""
  echo "  0) Identify CRDB & participants"
  echo "  1) Check K8s / operator health"
  echo "  2) Check REC & DB health from inside pod"
  echo "  3) Verify CRDB syncer state"
  echo "  4) Check inter-cluster network"
  echo "  5) Check TLS / cert issues"
  echo "  6) End-to-end data-plane connectivity test"
  echo "  a) Run all steps"
  echo "  q) Quit"
  echo ""
  read -p "Enter choice [0-6,a,q]: " choice

  case $choice in
    0) step_0 ;;
    1) step_1 ;;
    2) step_2 ;;
    3) step_3 ;;
    4) step_4 ;;
    5) step_5 ;;
    6) step_6 ;;
    a|A) run_all ;;
    q|Q) exit 0 ;;
    *) echo "Invalid choice" ;;
  esac
}

# Main execution
case "$STEP" in
  0) step_0 ;;
  1) step_1 ;;
  2) step_2 ;;
  3) step_3 ;;
  4) step_4 ;;
  5) step_5 ;;
  6) step_6 ;;
  all) run_all ;;
  *) show_menu ;;
esac

