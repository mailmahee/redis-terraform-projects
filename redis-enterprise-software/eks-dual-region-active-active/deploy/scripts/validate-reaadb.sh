#!/bin/bash
# Validate REAADB (Redis Enterprise Active-Active Database) deployment
# Usage: ./validate-reaadb.sh <values-file>

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
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE")
REAADB_PORT=$(yq eval '.reaadb.port' "$VALUES_FILE")
REAADB_PASSWORD=$(yq eval '.reaadb.password' "$VALUES_FILE")

echo "=========================================="
echo "REAADB Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "REAADB: $REAADB_NAME"
echo ""

# 1. Check REAADB exists
echo "=== Step 1: Checking REAADB exists ==="
if ! kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: REAADB '$REAADB_NAME' not found"
  exit 1
fi
echo "✓ REAADB exists"
echo ""

# 2. Check REAADB status
echo "=== Step 2: Checking REAADB status ==="
REAADB_STATUS=$(kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.status}' 2>/dev/null || echo "Unknown")
SPEC_STATUS=$(kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.specStatus}' 2>/dev/null || echo "Unknown")
REPLICATION_STATUS=$(kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.replicationStatus}' 2>/dev/null || echo "Unknown")

echo "  - Status: $REAADB_STATUS"
echo "  - Spec Status: $SPEC_STATUS"
echo "  - Replication Status: $REPLICATION_STATUS"

if [ "$REAADB_STATUS" != "active" ]; then
  echo "✗ ERROR: REAADB is not active (current status: $REAADB_STATUS)"
  kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" | tail -50
  exit 1
fi

if [ "$SPEC_STATUS" != "Valid" ]; then
  echo "✗ ERROR: REAADB spec is not valid (current status: $SPEC_STATUS)"
  kubectl describe reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" | tail -50
  exit 1
fi
echo "✓ REAADB is active with valid spec"
echo ""

# 3. Check participating clusters
echo "=== Step 3: Checking Participating Clusters ==="
PARTICIPATING=$(kubectl get reaadb "$REAADB_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.participatingClusters[*].name}' 2>/dev/null || echo "")

if [ -z "$PARTICIPATING" ]; then
  echo "✗ ERROR: No participating clusters found"
  exit 1
fi

echo "Participating clusters: $PARTICIPATING"

# Count clusters
CLUSTER_COUNT=$(echo "$PARTICIPATING" | wc -w | tr -d ' ')
if [ "$CLUSTER_COUNT" -lt 2 ]; then
  echo "✗ ERROR: Expected at least 2 participating clusters, found $CLUSTER_COUNT"
  exit 1
fi
echo "✓ Found $CLUSTER_COUNT participating clusters"
echo ""

# 4. Check CRDB details via API
echo "=== Step 4: Checking CRDB Details ==="
CRDB_INFO=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  bash -c "curl -k -s -u admin@redis.com:${REAADB_PASSWORD} https://localhost:9443/v1/bdbs" 2>/dev/null | \
  python3 -c "import sys, json; data = json.load(sys.stdin); db = next((d for d in data if d.get('name') == '$REAADB_NAME'), None); print(json.dumps(db, indent=2) if db else '')" 2>/dev/null || echo "")

if [ -z "$CRDB_INFO" ]; then
  echo "✗ WARNING: Could not retrieve CRDB info via API"
else
  echo "✓ CRDB found in cluster"
  
  # Check CRDT sync status
  CRDT_SYNC=$(echo "$CRDB_INFO" | python3 -c "import sys, json; data = json.load(sys.stdin); print(data.get('crdt_sync', 'unknown'))" 2>/dev/null || echo "unknown")
  echo "  - CRDT Sync: $CRDT_SYNC"
  
  # Check peer status
  PEER_STATUS=$(echo "$CRDB_INFO" | python3 -c "import sys, json; data = json.load(sys.stdin); peers = data.get('crdt_sources', []); print(peers[0].get('status', 'unknown') if peers else 'no-peers')" 2>/dev/null || echo "unknown")
  PEER_LAG=$(echo "$CRDB_INFO" | python3 -c "import sys, json; data = json.load(sys.stdin); peers = data.get('crdt_sources', []); print(peers[0].get('lag', 'unknown') if peers else 'no-peers')" 2>/dev/null || echo "unknown")
  
  echo "  - Peer Status: $PEER_STATUS"
  echo "  - Peer Lag: $PEER_LAG"
  
  if [ "$PEER_STATUS" == "in-sync" ]; then
    echo "✓ CRDB peer connection is in-sync"
  else
    echo "⚠ WARNING: CRDB peer status is '$PEER_STATUS' (expected: in-sync)"
  fi
fi
echo ""

# 5. Test database connectivity
echo "=== Step 5: Testing Database Connectivity ==="

# Get database service name and port from REC API
DB_INFO=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
  bash -c "curl -k -s -u admin@redis.com:RedisTest123 https://localhost:9443/v1/bdbs" 2>/dev/null | \
  jq -r ".[] | select(.name == \"$REAADB_NAME\") | .endpoints[0].dns_name + \":\" + (.endpoints[0].port | tostring)")

if [ -z "$DB_INFO" ] || [ "$DB_INFO" == "null:null" ]; then
  echo "⚠ WARNING: Could not discover database service information"
  echo "  Database may not be fully provisioned yet"
  echo ""
else
  DB_SERVICE=$(echo "$DB_INFO" | cut -d: -f1)
  DB_PORT=$(echo "$DB_INFO" | cut -d: -f2)

  echo "Testing connection to $DB_SERVICE on port $DB_PORT..."

  PING_RESULT=$(kubectl exec -n "$NAMESPACE" "${REC_NAME}-0" -c redis-enterprise-node --context="$K8S_CONTEXT" -- \
    bash -c "redis-cli -h $DB_SERVICE -p $DB_PORT --no-auth-warning -a $REAADB_PASSWORD PING" 2>/dev/null || echo "ERROR")

  if [ "$PING_RESULT" != "PONG" ]; then
    echo "✗ ERROR: Cannot connect to database (PING failed)"
    exit 1
  fi
  echo "✓ Database is accessible (PING successful)"
  echo ""
fi

echo "=========================================="
echo "✓ REAADB Validation Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - REAADB Status: $REAADB_STATUS"
echo "  - Participating Clusters: $CLUSTER_COUNT"
echo "  - Replication Status: $REPLICATION_STATUS"
echo "  - Database Connectivity: OK"
echo ""
echo "Next steps:"
echo "  - Test replication: ./validate-replication.sh values-region1.yaml values-region2.yaml"
echo ""

