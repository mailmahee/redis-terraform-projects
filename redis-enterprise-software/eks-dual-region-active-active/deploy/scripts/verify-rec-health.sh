#!/bin/bash
# Verify Redis Enterprise Cluster health using rlcheck and rladmin
# Usage: ./verify-rec-health.sh <values-file>

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
echo "Redis Enterprise Cluster Health Check"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "Namespace: $NAMESPACE"
echo ""

# Verify REC exists and is Running
echo "=== Checking REC Status ==="
if ! kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: REC '$REC_NAME' not found"
  exit 1
fi

REC_STATE=$(kubectl get rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" -o jsonpath='{.status.state}')
if [ "$REC_STATE" != "Running" ]; then
  echo "✗ ERROR: REC is not Running (current state: $REC_STATE)"
  exit 1
fi
echo "✓ REC is Running"
echo ""

# Run rlcheck on the first node
echo "=== Running rlcheck (Node Health Verification) ==="
echo "This verifies node configuration, services, and connectivity..."
echo ""

RLCHECK_OUTPUT=$(kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  rlcheck 2>&1 || true)

echo "$RLCHECK_OUTPUT"
echo ""

# Check if rlcheck passed
if echo "$RLCHECK_OUTPUT" | grep -q "PASS"; then
  echo "✓ rlcheck passed - node is healthy"
elif echo "$RLCHECK_OUTPUT" | grep -q "FAIL"; then
  echo "✗ WARNING: rlcheck reported failures"
  echo "  Review the output above for details"
  echo "  Contact Redis support if issues persist"
  # Don't exit - continue with other checks
else
  echo "⚠ rlcheck output unclear - review above"
fi
echo ""

# Run rladmin status to check cluster topology
echo "=== Running rladmin status (Cluster Topology) ==="
echo ""

RLADMIN_STATUS=$(kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  rladmin status 2>&1 || true)

echo "$RLADMIN_STATUS"
echo ""

# Parse and validate rladmin status output
echo "=== Analyzing Cluster Status ==="

# Check cluster health
if echo "$RLADMIN_STATUS" | grep -q "Cluster health: OK"; then
  echo "✓ Cluster health: OK"
else
  echo "✗ WARNING: Cluster health may have issues"
fi

# Count nodes
NODE_COUNT=$(echo "$RLADMIN_STATUS" | grep -c "^node:" || echo "0")
echo "✓ Nodes in cluster: $NODE_COUNT"

# Check for any non-OK statuses
if echo "$RLADMIN_STATUS" | grep -E "STATUS" | grep -v "OK" | grep -v "STATUS" &>/dev/null; then
  echo "⚠ WARNING: Some components may not be in OK status"
  echo "  Review the rladmin status output above"
fi

echo ""

# Run rladmin status databases to check for existing databases
echo "=== Checking for Existing Databases ==="
echo ""

RLADMIN_DBS=$(kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  rladmin status databases 2>&1 || true)

echo "$RLADMIN_DBS"
echo ""

# Count databases
DB_COUNT=$(echo "$RLADMIN_DBS" | grep -c "^db:" || echo "0")

if [ "$DB_COUNT" -eq 0 ]; then
  echo "✓ No databases found (clean cluster)"
else
  echo "⚠ Found $DB_COUNT database(s) in cluster"
  echo "  This may be expected if databases were created previously"
  echo "  Use 'rladmin status databases extra all' for detailed information"
fi

echo ""
echo "=========================================="
echo "Health Check Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - REC Status: $REC_STATE"
echo "  - Nodes: $NODE_COUNT"
echo "  - Databases: $DB_COUNT"
echo ""
echo "For detailed troubleshooting, you can run:"
echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- rlcheck"
echo "  kubectl exec -n $NAMESPACE redis-enterprise-0 -c redis-enterprise-node --context=$K8S_CONTEXT -- rladmin status extra all"
echo ""

