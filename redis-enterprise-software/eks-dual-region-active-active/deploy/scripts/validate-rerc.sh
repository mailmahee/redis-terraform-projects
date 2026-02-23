#!/bin/bash
# Validate RERC (Redis Enterprise Remote Cluster) resources
# Usage: ./validate-rerc.sh <values-file>

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
LOCAL_RERC=$(yq eval '.rerc.local.name' "$VALUES_FILE")
REMOTE_RERC=$(yq eval '.rerc.remote.name' "$VALUES_FILE")
LOCAL_REC=$(yq eval '.rerc.local.recName' "$VALUES_FILE")
REMOTE_REC=$(yq eval '.rerc.remote.recName' "$VALUES_FILE")

echo "=========================================="
echo "RERC Validation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "Local RERC: $LOCAL_RERC (references: $LOCAL_REC)"
echo "Remote RERC: $REMOTE_RERC (references: $REMOTE_REC)"
echo ""

# 1. Check local RERC exists
echo "=== Step 1: Checking Local RERC ==="
if ! kubectl get rerc "$LOCAL_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: Local RERC '$LOCAL_RERC' not found"
  exit 1
fi
echo "✓ Local RERC exists"

# Check local RERC status
LOCAL_STATUS=$(kubectl get rerc "$LOCAL_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.status}' 2>/dev/null || echo "Unknown")
LOCAL_IS_LOCAL=$(kubectl get rerc "$LOCAL_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.local}' 2>/dev/null || echo "Unknown")

echo "  - Status: $LOCAL_STATUS"
echo "  - Local: $LOCAL_IS_LOCAL"

if [ "$LOCAL_STATUS" != "Active" ]; then
  echo "✗ ERROR: Local RERC is not Active"
  kubectl describe rerc "$LOCAL_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" | tail -30
  exit 1
fi

if [ "$LOCAL_IS_LOCAL" != "true" ]; then
  echo "✗ ERROR: Local RERC should have 'local: true' but has 'local: $LOCAL_IS_LOCAL'"
  echo "  This indicates the recName field may be incorrect"
  exit 1
fi
echo "✓ Local RERC is Active and correctly marked as local"
echo ""

# 2. Check remote RERC exists
echo "=== Step 2: Checking Remote RERC ==="
if ! kubectl get rerc "$REMOTE_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" &>/dev/null; then
  echo "✗ ERROR: Remote RERC '$REMOTE_RERC' not found"
  exit 1
fi
echo "✓ Remote RERC exists"

# Check remote RERC status
REMOTE_STATUS=$(kubectl get rerc "$REMOTE_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.status}' 2>/dev/null || echo "Unknown")
REMOTE_IS_LOCAL=$(kubectl get rerc "$REMOTE_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.local}' 2>/dev/null || echo "Unknown")

echo "  - Status: $REMOTE_STATUS"
echo "  - Local: $REMOTE_IS_LOCAL"

if [ "$REMOTE_STATUS" != "Active" ]; then
  echo "✗ ERROR: Remote RERC is not Active"
  kubectl describe rerc "$REMOTE_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" | tail -30
  exit 1
fi

if [ "$REMOTE_IS_LOCAL" != "false" ]; then
  echo "✗ ERROR: Remote RERC should have 'local: false' but has 'local: $REMOTE_IS_LOCAL'"
  echo "  This indicates the recName field may be incorrect"
  exit 1
fi
echo "✓ Remote RERC is Active and correctly marked as remote"
echo ""

# 3. Verify recName fields
echo "=== Step 3: Verifying recName Configuration ==="
LOCAL_REC_NAME=$(kubectl get rerc "$LOCAL_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.spec.recName}' 2>/dev/null || echo "")
REMOTE_REC_NAME=$(kubectl get rerc "$REMOTE_RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
  -o jsonpath='{.spec.recName}' 2>/dev/null || echo "")

echo "Local RERC references REC: $LOCAL_REC_NAME (expected: $LOCAL_REC)"
echo "Remote RERC references REC: $REMOTE_REC_NAME (expected: $REMOTE_REC)"

if [ "$LOCAL_REC_NAME" != "$LOCAL_REC" ]; then
  echo "✗ ERROR: Local RERC recName mismatch"
  exit 1
fi

if [ "$REMOTE_REC_NAME" != "$REMOTE_REC" ]; then
  echo "✗ ERROR: Remote RERC recName mismatch"
  exit 1
fi
echo "✓ recName fields are correct"
echo ""

# 4. Display full RERC status
echo "=== Step 4: Full RERC Status ==="
kubectl get rerc -n "$NAMESPACE" --context="$K8S_CONTEXT"
echo ""

echo "=========================================="
echo "✓ RERC Validation Complete for $CLUSTER_NAME"
echo "=========================================="
echo ""
echo "Summary:"
echo "  - Local RERC ($LOCAL_RERC): Active, local=true"
echo "  - Remote RERC ($REMOTE_RERC): Active, local=false"
echo ""
echo "Next steps:"
echo "  - Deploy REAADB: ./deploy-reaadb.sh $VALUES_FILE"
echo ""

