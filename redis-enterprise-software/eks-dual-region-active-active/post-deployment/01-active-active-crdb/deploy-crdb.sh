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

# Use full ARN contexts for kubectl
REGION1_CONTEXT="arn:aws:eks:${AWS_REGION1}:735486936198:cluster/${REGION1_CLUSTER_NAME}"
REGION2_CONTEXT="arn:aws:eks:${AWS_REGION2}:735486936198:cluster/${REGION2_CLUSTER_NAME}"

echo "CRDB Configuration:"
echo "  Name: $CRDB_NAME"
echo "  Memory: $CRDB_MEMORY"
echo "  Shards: $CRDB_SHARDS"
echo "  Replication: $CRDB_REPLICATION"
echo "  Persistence: $CRDB_PERSISTENCE"
echo "  Eviction Policy: $CRDB_EVICTION_POLICY"
echo ""
echo "Participating Clusters:"
echo "  Region 1: $REGION1_REC_NAME"
echo "  Region 2: $REGION2_REC_NAME"
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

# Get REC credentials
echo -e "${BLUE}🔐 Getting REC credentials...${NC}"
REC1_USER=$(kubectl get secret $REGION1_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
REC1_PASS=$(kubectl get secret $REGION1_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
REC2_USER=$(kubectl get secret $REGION2_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.data.username}' 2>/dev/null | base64 -d || echo "")
REC2_PASS=$(kubectl get secret $REGION2_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")

if [ -z "$REC1_USER" ] || [ -z "$REC1_PASS" ] || [ -z "$REC2_USER" ] || [ -z "$REC2_PASS" ]; then
    echo -e "${RED}❌ Failed to get REC credentials${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Credentials retrieved${NC}"
echo ""

# Get REC API endpoints from NGINX Ingress LoadBalancer
echo -e "${BLUE}🔍 Getting NGINX Ingress LoadBalancer endpoints...${NC}"

# Get the actual NLB DNS names from the NGINX Ingress services
REC1_API=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context $REGION1_CONTEXT -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
REC2_API=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context $REGION2_CONTEXT -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -z "$REC1_API" ] || [ -z "$REC2_API" ]; then
    echo -e "${RED}❌ Failed to get NGINX Ingress LoadBalancer endpoints${NC}"
    echo "Please ensure NGINX Ingress is deployed and LoadBalancer is provisioned."
    exit 1
fi

echo "  Region 1 API: $REC1_API"
echo "  Region 2 API: $REC2_API"
echo -e "${GREEN}✅ API endpoints configured${NC}"
echo ""

# Create credential secrets for remote clusters
echo -e "${BLUE}🔐 Creating credential secrets for RERC resources...${NC}"

# Secret in Region 1 for local RERC (must be named redis-enterprise-<RERC name>)
cat > "$SCRIPT_DIR/region1-local-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-enterprise-${REGION1_REC_NAME}
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: "$REC1_USER"
  password: "$REC1_PASS"
EOF

# Secret in Region 1 for accessing Region 2 (must be named redis-enterprise-<RERC name>)
cat > "$SCRIPT_DIR/region2-remote-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-enterprise-${REGION2_REC_NAME}
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: "$REC2_USER"
  password: "$REC2_PASS"
EOF

# Secret in Region 2 for local RERC (must be named redis-enterprise-<RERC name>)
cat > "$SCRIPT_DIR/region2-local-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-enterprise-${REGION2_REC_NAME}
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: "$REC2_USER"
  password: "$REC2_PASS"
EOF

# Secret in Region 2 for accessing Region 1 (must be named redis-enterprise-<RERC name>)
cat > "$SCRIPT_DIR/region1-remote-secret.yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: redis-enterprise-${REGION1_REC_NAME}
  namespace: $NAMESPACE
type: Opaque
stringData:
  username: "$REC1_USER"
  password: "$REC1_PASS"
EOF

kubectl apply -f "$SCRIPT_DIR/region1-local-secret.yaml" --context $REGION1_CONTEXT
kubectl apply -f "$SCRIPT_DIR/region2-remote-secret.yaml" --context $REGION1_CONTEXT
kubectl apply -f "$SCRIPT_DIR/region2-local-secret.yaml" --context $REGION2_CONTEXT
kubectl apply -f "$SCRIPT_DIR/region1-remote-secret.yaml" --context $REGION2_CONTEXT

echo -e "${GREEN}✅ Credential secrets created${NC}"
echo ""

# NOTE: RERC resources are now created by Terraform with Route53 FQDNs
# This script only creates the secrets. If you need to manually create RERCs,
# uncomment the section below and update the apiFqdnUrl to use Route53 FQDNs.

echo -e "${BLUE}🔗 Verifying Remote Cluster resources...${NC}"

# Verify RERCs exist
RERC1_EXISTS=$(kubectl get rerc $REGION1_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT 2>/dev/null && echo "yes" || echo "no")
RERC2_EXISTS=$(kubectl get rerc $REGION2_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT 2>/dev/null && echo "yes" || echo "no")

if [ "$RERC1_EXISTS" != "yes" ] || [ "$RERC2_EXISTS" != "yes" ]; then
    echo -e "${RED}❌ RERC resources not found. Please run 'terraform apply' first.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Remote Cluster resources verified${NC}"
echo ""

# Wait for RERC resources to be ready
echo -e "${YELLOW}⏳ Waiting for RERC resources to be ready...${NC}"
sleep 10

# Verify RERC status
RERC1_LOCAL=$(kubectl get rerc $REGION1_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.status.status}' 2>/dev/null || echo "pending")
RERC1_REMOTE=$(kubectl get rerc $REGION2_REC_NAME -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.status.status}' 2>/dev/null || echo "pending")
RERC2_LOCAL=$(kubectl get rerc $REGION2_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.status.status}' 2>/dev/null || echo "pending")
RERC2_REMOTE=$(kubectl get rerc $REGION1_REC_NAME -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.status.status}' 2>/dev/null || echo "pending")

echo "  Region 1 - Local RERC: $RERC1_LOCAL"
echo "  Region 1 - Remote RERC (to Region 2): $RERC1_REMOTE"
echo "  Region 2 - Local RERC: $RERC2_LOCAL"
echo "  Region 2 - Remote RERC (to Region 1): $RERC2_REMOTE"
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

