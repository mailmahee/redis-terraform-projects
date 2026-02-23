#!/bin/bash
# Deploy REAADB (Active-Active Database)
# This should be run AFTER both regions are deployed and validated
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$DEPLOY_DIR/templates"

VALUES_FILE=$1

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file>"
  echo "Example: $0 ../values-region1.yaml"
  exit 1
fi

echo "=== Deploying REAADB ==="

K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE")
DATABASE_PORT=$(yq eval '.reaadb.databasePort' "$VALUES_FILE")
SECRET_NAME=$(yq eval '.reaadb.secretName' "$VALUES_FILE")
MEMORY_SIZE=$(yq eval '.reaadb.memorySize' "$VALUES_FILE")
SHARD_COUNT=$(yq eval '.reaadb.shardCount' "$VALUES_FILE")
REPLICATION=$(yq eval '.reaadb.replication' "$VALUES_FILE")
EVICTION_POLICY=$(yq eval '.reaadb.evictionPolicy' "$VALUES_FILE")

# Build participating clusters list
PARTICIPATING_CLUSTERS=""
first=true
for cluster in $(yq eval '.reaadb.participatingClusters[]' "$VALUES_FILE"); do
  if [ "$first" = true ]; then
    PARTICIPATING_CLUSTERS="    - name: ${cluster}"
    first=false
  else
    PARTICIPATING_CLUSTERS="${PARTICIPATING_CLUSTERS}
    - name: ${cluster}"
  fi
done

echo "REAADB Name: $REAADB_NAME"
echo "Database Port: $DATABASE_PORT"
echo "Memory Size: $MEMORY_SIZE"
echo "Shard Count: $SHARD_COUNT"
echo "Replication: $REPLICATION"
echo ""

# Pre-flight checks
echo "Running pre-flight checks..."

# Check that all participating RERCs are Active
echo "Checking RERC status..."
for cluster in $(yq eval '.reaadb.participatingClusters[]' "$VALUES_FILE"); do
  STATUS=$(kubectl get rerc "$cluster" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "NotFound")
  
  if [ "$STATUS" != "Active" ]; then
    echo "ERROR: RERC $cluster is not Active (status: $STATUS)"
    echo "Please ensure both regions are deployed and all RERCs are Active"
    exit 1
  fi
  echo "✓ RERC $cluster is Active"
done

# Check for existing REAADB
if kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo ""
  echo "WARNING: REAADB $REAADB_NAME already exists"
  read -p "Do you want to delete and recreate it? (yes/no): " CONFIRM
  if [ "$CONFIRM" = "yes" ]; then
    echo "Deleting existing REAADB..."
    bash "$SCRIPT_DIR/cleanup-reaadb.sh" "$VALUES_FILE"
  else
    echo "Aborted"
    exit 1
  fi
fi

echo ""
echo "Creating database secret if it doesn't exist..."
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  kubectl create secret generic "$SECRET_NAME" \
    -n "$NAMESPACE" \
    --context="$K8S_CONTEXT" \
    --from-literal=password=RedisTest123
  echo "✓ Secret $SECRET_NAME created"
else
  echo "✓ Secret $SECRET_NAME already exists"
fi

echo ""
echo "Deploying REAADB..."

# Generate REAADB manifest from template
export NAMESPACE
export REAADB_NAME
export DATABASE_PORT
export SECRET_NAME
export MEMORY_SIZE
export SHARD_COUNT
export REPLICATION
export EVICTION_POLICY
export PARTICIPATING_CLUSTERS

envsubst < "$TEMPLATES_DIR/reaadb.yaml.tpl" | \
  kubectl apply --context="$K8S_CONTEXT" -f -

echo "✓ REAADB manifest applied"

# Wait for REAADB to become active
echo ""
echo "Waiting for REAADB to become active (this may take 1-2 minutes)..."
for i in {1..120}; do
  STATUS=$(kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
    -o jsonpath='{.status.status}' 2>/dev/null || echo "")
  
  if [ "$STATUS" = "active" ]; then
    echo "✓ REAADB is active!"
    break
  elif [ "$STATUS" = "creation-failed" ]; then
    echo "ERROR: REAADB creation failed"
    kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT"
    kubectl logs -n "$NAMESPACE" deployment/redis-enterprise-operator --tail=50 --context="$K8S_CONTEXT" | grep -i "$REAADB_NAME"
    exit 1
  fi
  
  if [ $((i % 10)) -eq 0 ]; then
    echo "Status: $STATUS (waiting...)"
  fi
  
  if [ $i -eq 120 ]; then
    echo "ERROR: REAADB did not become active after 2 minutes (status: $STATUS)"
    kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT"
    exit 1
  fi
  
  sleep 1
done

echo ""
echo "=== REAADB Deployment Complete ==="
kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT"

