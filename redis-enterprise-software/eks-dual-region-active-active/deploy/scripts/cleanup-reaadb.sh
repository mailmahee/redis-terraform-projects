#!/bin/bash
# Cleanup REAADB and orphaned databases
set -e

VALUES_FILE=$1

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file>"
  exit 1
fi

echo "=== Cleaning up REAADB and orphaned databases ==="

K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE")
USERNAME=$(yq eval '.credentials.username' "$VALUES_FILE")
PASSWORD=$(yq eval '.credentials.password' "$VALUES_FILE")

# Delete REAADB if it exists
if kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "Deleting REAADB: $REAADB_NAME"
  
  # Remove finalizers
  kubectl patch reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
    --type=merge -p '{"metadata":{"finalizers":[]}}' || true
  
  # Delete the resource
  kubectl delete reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" --timeout=60s || true
  
  echo "✓ REAADB deleted"
else
  echo "No REAADB found"
fi

# Check for orphaned databases
echo "Checking for orphaned databases..."
DATABASES=$(kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  bash -c "curl -k -s -u $USERNAME:$PASSWORD https://localhost:9443/v1/bdbs" | jq -r '.[] | .uid' 2>/dev/null || echo "")

if [ -z "$DATABASES" ]; then
  echo "✓ No orphaned databases found"
else
  echo "Found orphaned databases, deleting..."
  for DB_UID in $DATABASES; do
    echo "Deleting database UID: $DB_UID"
    kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
      bash -c "curl -k -s -u $USERNAME:$PASSWORD -X DELETE https://localhost:9443/v1/bdbs/$DB_UID" || true
  done
  echo "✓ Orphaned databases deleted"
fi

# Wait for databases to be fully deleted
echo "Waiting for databases to be fully deleted..."
sleep 5

# Verify cleanup
DB_COUNT=$(kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  bash -c "curl -k -s -u $USERNAME:$PASSWORD https://localhost:9443/v1/bdbs" | jq '. | length' 2>/dev/null || echo "0")

if [ "$DB_COUNT" = "0" ]; then
  echo "✓ All databases cleaned up"
else
  echo "WARNING: $DB_COUNT database(s) still exist"
fi

echo ""
echo "=== Cleanup Complete ==="

