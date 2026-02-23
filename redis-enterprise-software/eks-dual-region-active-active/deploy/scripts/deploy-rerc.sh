#!/bin/bash
# Deploy RERC resources
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$DEPLOY_DIR/templates"

VALUES_FILE=$1

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file>"
  exit 1
fi

echo "Loading configuration..."
K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REC_NAME=$(yq eval '.rec.name' "$VALUES_FILE")
USERNAME=$(yq eval '.credentials.username' "$VALUES_FILE")
PASSWORD=$(yq eval '.credentials.password' "$VALUES_FILE")

# Local RERC
LOCAL_RERC_NAME=$(yq eval '.rerc.local.name' "$VALUES_FILE")
LOCAL_REC_NAME=$(yq eval '.rerc.local.recName' "$VALUES_FILE")
LOCAL_API_FQDN_URL=$(yq eval '.rerc.local.apiFqdnUrl' "$VALUES_FILE")
LOCAL_DB_FQDN_SUFFIX=$(yq eval '.rerc.local.dbFqdnSuffix' "$VALUES_FILE")
LOCAL_SECRET_NAME=$(yq eval '.rerc.local.secretName' "$VALUES_FILE")

# Remote RERC
REMOTE_RERC_NAME=$(yq eval '.rerc.remote.name' "$VALUES_FILE")
REMOTE_REC_NAME=$(yq eval '.rerc.remote.recName' "$VALUES_FILE")
REMOTE_API_FQDN_URL=$(yq eval '.rerc.remote.apiFqdnUrl' "$VALUES_FILE")
REMOTE_DB_FQDN_SUFFIX=$(yq eval '.rerc.remote.dbFqdnSuffix' "$VALUES_FILE")
REMOTE_SECRET_NAME=$(yq eval '.rerc.remote.secretName' "$VALUES_FILE")

echo "Deploying RERC resources..."

# Create secret for local RERC
echo "Creating secret for local RERC: $LOCAL_SECRET_NAME"
kubectl create secret generic "$LOCAL_SECRET_NAME" \
  -n "$NAMESPACE" \
  --from-literal=username="$USERNAME" \
  --from-literal=password="$PASSWORD" \
  --context="$K8S_CONTEXT" \
  --dry-run=client -o yaml | kubectl apply --context="$K8S_CONTEXT" -f -

# Create secret for remote RERC
echo "Creating secret for remote RERC: $REMOTE_SECRET_NAME"
kubectl create secret generic "$REMOTE_SECRET_NAME" \
  -n "$NAMESPACE" \
  --from-literal=username="$USERNAME" \
  --from-literal=password="$PASSWORD" \
  --context="$K8S_CONTEXT" \
  --dry-run=client -o yaml | kubectl apply --context="$K8S_CONTEXT" -f -

echo "✓ Secrets created"

# Deploy local RERC
echo "Deploying local RERC: $LOCAL_RERC_NAME (recName: $LOCAL_REC_NAME)"
export NAMESPACE
export REC_NAME="$LOCAL_REC_NAME"
export RERC_NAME="$LOCAL_RERC_NAME"
export API_FQDN_URL="$LOCAL_API_FQDN_URL"
export DB_FQDN_SUFFIX="$LOCAL_DB_FQDN_SUFFIX"
export SECRET_NAME="$LOCAL_SECRET_NAME"

envsubst < "$TEMPLATES_DIR/rerc.yaml.tpl" | \
  kubectl apply --context="$K8S_CONTEXT" -f -

# Deploy remote RERC
echo "Deploying remote RERC: $REMOTE_RERC_NAME (recName: $REMOTE_REC_NAME)"
export REC_NAME="$REMOTE_REC_NAME"
export RERC_NAME="$REMOTE_RERC_NAME"
export API_FQDN_URL="$REMOTE_API_FQDN_URL"
export DB_FQDN_SUFFIX="$REMOTE_DB_FQDN_SUFFIX"
export SECRET_NAME="$REMOTE_SECRET_NAME"

envsubst < "$TEMPLATES_DIR/rerc.yaml.tpl" | \
  kubectl apply --context="$K8S_CONTEXT" -f -

echo "✓ RERC resources deployed"

# Wait for RERCs to become Active
echo "Waiting for RERCs to become Active..."
for RERC in "$LOCAL_RERC_NAME" "$REMOTE_RERC_NAME"; do
  echo "Checking RERC: $RERC"
  for i in {1..60}; do
    STATUS=$(kubectl get rerc "$RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT" \
      -o jsonpath='{.status.status}' 2>/dev/null || echo "")
    
    if [ "$STATUS" = "Active" ]; then
      echo "✓ RERC $RERC is Active"
      break
    elif [ "$STATUS" = "Error" ]; then
      echo "ERROR: RERC $RERC is in Error state"
      kubectl describe rerc "$RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT"
      exit 1
    fi
    
    if [ $i -eq 60 ]; then
      echo "ERROR: RERC $RERC did not become Active after 60 seconds (status: $STATUS)"
      kubectl describe rerc "$RERC" -n "$NAMESPACE" --context="$K8S_CONTEXT"
      exit 1
    fi
    
    sleep 1
  done
done

echo "✓ All RERCs are Active"

