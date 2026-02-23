#!/bin/bash
# Validate bidirectional replication between regions
# Usage: ./validate-replication.sh <values-file-region1> <values-file-region2>

set -e

VALUES_FILE_R1=$1
VALUES_FILE_R2=$2

if [ -z "$VALUES_FILE_R1" ] || [ -z "$VALUES_FILE_R2" ]; then
  echo "Usage: $0 <values-file-region1> <values-file-region2>"
  exit 1
fi

if [ ! -f "$VALUES_FILE_R1" ]; then
  echo "ERROR: Values file not found: $VALUES_FILE_R1"
  exit 1
fi

if [ ! -f "$VALUES_FILE_R2" ]; then
  echo "ERROR: Values file not found: $VALUES_FILE_R2"
  exit 1
fi

# Load configuration
if ! command -v yq &> /dev/null; then
  echo "ERROR: yq is required but not installed."
  exit 1
fi

# Region 1 config
K8S_CONTEXT_R1=$(yq eval '.cluster.k8s_context' "$VALUES_FILE_R1")
NAMESPACE_R1=$(yq eval '.rec.namespace' "$VALUES_FILE_R1")
REC_NAME_R1=$(yq eval '.rec.name' "$VALUES_FILE_R1")
CLUSTER_NAME_R1=$(yq eval '.cluster.name' "$VALUES_FILE_R1")
REAADB_NAME=$(yq eval '.reaadb.name' "$VALUES_FILE_R1")
REAADB_PORT=$(yq eval '.reaadb.port' "$VALUES_FILE_R1")
REAADB_PASSWORD=$(yq eval '.reaadb.password' "$VALUES_FILE_R1")

# Region 2 config
K8S_CONTEXT_R2=$(yq eval '.cluster.k8s_context' "$VALUES_FILE_R2")
NAMESPACE_R2=$(yq eval '.rec.namespace' "$VALUES_FILE_R2")
REC_NAME_R2=$(yq eval '.rec.name' "$VALUES_FILE_R2")
CLUSTER_NAME_R2=$(yq eval '.cluster.name' "$VALUES_FILE_R2")

echo "=========================================="
echo "Bidirectional Replication Test"
echo "=========================================="
echo "Region 1: $CLUSTER_NAME_R1 (context: $K8S_CONTEXT_R1)"
echo "Region 2: $CLUSTER_NAME_R2 (context: $K8S_CONTEXT_R2)"
echo "Database: $REAADB_NAME"
echo ""

# Get database service name and port from REC API
echo "Discovering database service and port..."
DB_INFO=$(kubectl exec -n "$NAMESPACE_R1" "${REC_NAME_R1}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R1" -- \
  bash -c "curl -k -s -u admin@redis.com:RedisTest123 https://localhost:9443/v1/bdbs" 2>/dev/null | \
  jq -r ".[] | select(.name == \"$REAADB_NAME\") | .endpoints[0].dns_name + \":\" + (.endpoints[0].port | tostring)")

if [ -z "$DB_INFO" ] || [ "$DB_INFO" == "null:null" ]; then
  echo "✗ ERROR: Could not discover database service information"
  echo "  Database may not be fully provisioned yet"
  exit 1
fi

DB_SERVICE=$(echo "$DB_INFO" | cut -d: -f1)
DB_PORT=$(echo "$DB_INFO" | cut -d: -f2)

echo "✓ Database service: $DB_SERVICE"
echo "✓ Database port: $DB_PORT"
echo ""

# 1. Test Region 1 → Region 2 replication
echo "=== Test 1: Region 1 → Region 2 Replication ==="
echo "Writing test key to Region 1..."

TIMESTAMP=$(date +%s)
TEST_KEY_R1="test-region1-${TIMESTAMP}"
TEST_VALUE_R1="Written from Region 1 at $(date)"

WRITE_RESULT=$(kubectl exec -n "$NAMESPACE_R1" "${REC_NAME_R1}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R1" -- \
  bash -c "redis-cli -h $DB_SERVICE -p $DB_PORT --no-auth-warning -a $REAADB_PASSWORD SET $TEST_KEY_R1 '$TEST_VALUE_R1'" 2>/dev/null || echo "ERROR")

if [ "$WRITE_RESULT" != "OK" ]; then
  echo "✗ ERROR: Failed to write to Region 1"
  exit 1
fi
echo "✓ Write successful in Region 1"

echo "Waiting 5 seconds for replication..."
sleep 5

echo "Reading from Region 2..."
# Get database service for region 2
DB_INFO_R2=$(kubectl exec -n "$NAMESPACE_R2" "${REC_NAME_R2}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R2" -- \
  bash -c "curl -k -s -u admin@redis.com:RedisTest123 https://localhost:9443/v1/bdbs" 2>/dev/null | \
  jq -r ".[] | select(.name == \"$REAADB_NAME\") | .endpoints[0].dns_name + \":\" + (.endpoints[0].port | tostring)")
DB_SERVICE_R2=$(echo "$DB_INFO_R2" | cut -d: -f1)
DB_PORT_R2=$(echo "$DB_INFO_R2" | cut -d: -f2)

READ_RESULT=$(kubectl exec -n "$NAMESPACE_R2" "${REC_NAME_R2}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R2" -- \
  bash -c "redis-cli -h $DB_SERVICE_R2 -p $DB_PORT_R2 --no-auth-warning -a $REAADB_PASSWORD GET $TEST_KEY_R1" 2>/dev/null || echo "ERROR")

if [ "$READ_RESULT" == "ERROR" ] || [ -z "$READ_RESULT" ]; then
  echo "✗ ERROR: Failed to read from Region 2"
  echo "  Replication from Region 1 → Region 2 is NOT working"
  exit 1
fi

if [ "$READ_RESULT" == "$TEST_VALUE_R1" ]; then
  echo "✓ Replication successful: Region 1 → Region 2"
  echo "  Value: $READ_RESULT"
else
  echo "✗ ERROR: Value mismatch"
  echo "  Expected: $TEST_VALUE_R1"
  echo "  Got: $READ_RESULT"
  exit 1
fi
echo ""

# 2. Test Region 2 → Region 1 replication
echo "=== Test 2: Region 2 → Region 1 Replication ==="
echo "Writing test key to Region 2..."

TEST_KEY_R2="test-region2-${TIMESTAMP}"
TEST_VALUE_R2="Written from Region 2 at $(date)"

WRITE_RESULT=$(kubectl exec -n "$NAMESPACE_R2" "${REC_NAME_R2}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R2" -- \
  bash -c "redis-cli -h $DB_SERVICE_R2 -p $DB_PORT_R2 --no-auth-warning -a $REAADB_PASSWORD SET $TEST_KEY_R2 '$TEST_VALUE_R2'" 2>/dev/null || echo "ERROR")

if [ "$WRITE_RESULT" != "OK" ]; then
  echo "✗ ERROR: Failed to write to Region 2"
  exit 1
fi
echo "✓ Write successful in Region 2"

echo "Waiting 5 seconds for replication..."
sleep 5

echo "Reading from Region 1..."
READ_RESULT=$(kubectl exec -n "$NAMESPACE_R1" "${REC_NAME_R1}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R1" -- \
  bash -c "redis-cli -h $DB_SERVICE -p $DB_PORT --no-auth-warning -a $REAADB_PASSWORD GET $TEST_KEY_R2" 2>/dev/null || echo "ERROR")

if [ "$READ_RESULT" == "ERROR" ] || [ -z "$READ_RESULT" ]; then
  echo "✗ ERROR: Failed to read from Region 1"
  echo "  Replication from Region 2 → Region 1 is NOT working"
  exit 1
fi

if [ "$READ_RESULT" == "$TEST_VALUE_R2" ]; then
  echo "✓ Replication successful: Region 2 → Region 1"
  echo "  Value: $READ_RESULT"
else
  echo "✗ ERROR: Value mismatch"
  echo "  Expected: $TEST_VALUE_R2"
  echo "  Got: $READ_RESULT"
  exit 1
fi
echo ""

# 3. Cleanup test keys
echo "=== Cleanup ==="
echo "Removing test keys..."
kubectl exec -n "$NAMESPACE_R1" "${REC_NAME_R1}-0" -c redis-enterprise-node --context="$K8S_CONTEXT_R1" -- \
  bash -c "redis-cli -h $DB_SERVICE -p $DB_PORT --no-auth-warning -a $REAADB_PASSWORD DEL $TEST_KEY_R1 $TEST_KEY_R2" &>/dev/null || true
echo "✓ Test keys removed"
echo ""

echo "=========================================="
echo "✓ Bidirectional Replication Test PASSED"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Region 1 → Region 2: Working"
echo "  ✓ Region 2 → Region 1: Working"
echo ""
echo "Active-Active database is fully operational!"
echo ""

