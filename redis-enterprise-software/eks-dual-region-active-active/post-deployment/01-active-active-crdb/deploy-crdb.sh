#!/bin/bash

#==============================================================================
# ACTIVE-ACTIVE CRDB DEPLOYMENT SCRIPT
#==============================================================================
# This script deploys a Redis Enterprise Active-Active database (CRDB)
# across two regions using configuration from config.env
#==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.env"

echo ""
echo "=========================================================================="
echo "  Active-Active CRDB Deployment"
echo "=========================================================================="
echo ""

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: config.env not found at $CONFIG_FILE${NC}"
    echo "Please run 'terraform apply' first to generate this file."
    exit 1
fi

echo -e "${BLUE}📋 Loading configuration...${NC}"
source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=(
    "PROJECT_PREFIX"
    "CRDB_NAME"
    "REGION1_REC_NAME"
    "REGION2_REC_NAME"
    "NAMESPACE"
    "REGION1_CONTEXT"
    "REGION2_CONTEXT"
    "CRDB_MEMORY"
    "CRDB_SHARDS"
    "CRDB_REPLICATION"
    "CRDB_PERSISTENCE"
    "CRDB_EVICTION_POLICY"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}❌ Required variable $var is not set${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✅ Configuration loaded${NC}"
echo ""
echo "CRDB Configuration:"
echo "  Name: $CRDB_NAME"
echo "  Memory: $CRDB_MEMORY"
echo "  Shards: $CRDB_SHARDS"
echo "  Replication: $CRDB_REPLICATION"
echo "  Persistence: $CRDB_PERSISTENCE"
echo "  Eviction Policy: $CRDB_EVICTION_POLICY"
echo ""
echo "Participating Clusters:"
echo "  Region 1: $REGION1_REC_NAME (context: $REGION1_CONTEXT)"
echo "  Region 2: $REGION2_REC_NAME (context: $REGION2_CONTEXT)"
echo ""

# Generate REAADB manifest from template
echo -e "${BLUE}📝 Generating REAADB manifest...${NC}"

cat > "$SCRIPT_DIR/reaadb.yaml" <<EOF
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseActiveActiveDatabase
metadata:
  name: $CRDB_NAME
  namespace: $NAMESPACE
spec:
  participatingClusters:
    - name: $REGION1_REC_NAME
    - name: $REGION2_REC_NAME
  
  globalConfigurations:
    evictionPolicy: $CRDB_EVICTION_POLICY
    memorySize: $CRDB_MEMORY
    ossCluster: false
    persistence: $CRDB_PERSISTENCE
    replication: $CRDB_REPLICATION
    shardCount: $CRDB_SHARDS
    type: redis
EOF

echo -e "${GREEN}✅ Manifest generated: reaadb.yaml${NC}"
echo ""

# Verify REC status before deployment
echo -e "${BLUE}🔍 Verifying Redis Enterprise Clusters...${NC}"

REC1_STATUS=$(kubectl get rec $REGION1_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")
REC2_STATUS=$(kubectl get rec $REGION2_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")

if [ "$REC1_STATUS" != "Running" ]; then
    echo -e "${RED}❌ REC $REGION1_REC_NAME is not Running (Status: $REC1_STATUS)${NC}"
    echo "Please ensure the Redis Enterprise Cluster is deployed and running."
    exit 1
fi

if [ "$REC2_STATUS" != "Running" ]; then
    echo -e "${RED}❌ REC $REGION2_REC_NAME is not Running (Status: $REC2_STATUS)${NC}"
    echo "Please ensure the Redis Enterprise Cluster is deployed and running."
    exit 1
fi

echo -e "${GREEN}✅ Both RECs are Running${NC}"
echo ""

# Deploy REAADB
echo -e "${BLUE}🚀 Deploying Active-Active database...${NC}"
kubectl apply -f "$SCRIPT_DIR/reaadb.yaml" --context $REGION1_CONTEXT

echo -e "${YELLOW}⏳ Waiting for REAADB to be created...${NC}"
sleep 10

# Wait for REAADB to be active
echo -e "${YELLOW}⏳ Waiting for REAADB to become active (this may take 2-3 minutes)...${NC}"
TIMEOUT=300
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    STATUS=$(kubectl get reaadb $CRDB_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.status.status}' 2>/dev/null || echo "pending")
    
    if [ "$STATUS" = "active" ]; then
        echo -e "${GREEN}✅ REAADB is active!${NC}"
        break
    fi
    
    echo "  Status: $STATUS (${ELAPSED}s elapsed)"
    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo -e "${RED}❌ Timeout waiting for REAADB to become active${NC}"
    echo "Check status with: kubectl get reaadb $CRDB_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o yaml"
    exit 1
fi

echo ""
echo "=========================================================================="
echo -e "${GREEN}✅ Active-Active CRDB Deployed Successfully!${NC}"
echo "=========================================================================="
echo ""
echo "Database Details:"
echo "  Name: $CRDB_NAME"
echo "  Namespace: $NAMESPACE"
echo ""
echo "Verification Commands:"
echo "  # Check REAADB status in Region 1:"
echo "  kubectl get reaadb $CRDB_NAME -n $NAMESPACE --context $REGION1_CONTEXT"
echo ""
echo "  # Check REAADB status in Region 2:"
echo "  kubectl get reaadb $CRDB_NAME -n $NAMESPACE --context $REGION2_CONTEXT"
echo ""
echo "  # Get database connection details:"
echo "  kubectl get reaadb $CRDB_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o yaml"
echo ""
echo "=========================================================================="
echo ""

