#!/bin/bash

#==============================================================================
# CREATE LOADBALANCER SERVICES FOR CROSS-REGION RERC
#==============================================================================
# This script creates LoadBalancer services to expose REC API endpoints
# for cross-region Active-Active database communication
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.env"

echo ""
echo "=========================================================================="
echo "  Create LoadBalancer Services for Cross-Region RERC"
echo "=========================================================================="
echo ""

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: config.env not found${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Use full ARN contexts
REGION1_CONTEXT="arn:aws:eks:${AWS_REGION1}:735486936198:cluster/${REGION1_CLUSTER_NAME}"
REGION2_CONTEXT="arn:aws:eks:${AWS_REGION2}:735486936198:cluster/${REGION2_CLUSTER_NAME}"

echo -e "${BLUE}📋 Configuration:${NC}"
echo "  Region 1 REC: $REGION1_REC_NAME"
echo "  Region 2 REC: $REGION2_REC_NAME"
echo "  Namespace: $NAMESPACE"
echo ""

# Create LoadBalancer service for Region 1 REC API
echo -e "${BLUE}🔧 Creating LoadBalancer service for Region 1 REC API...${NC}"
cat > "$SCRIPT_DIR/region1-api-lb.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${REGION1_REC_NAME}-api-lb
  namespace: $NAMESPACE
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
spec:
  type: LoadBalancer
  selector:
    app: redis-enterprise
    redis.io/cluster: $REGION1_REC_NAME
  ports:
    - name: api
      port: 9443
      targetPort: 9443
      protocol: TCP
EOF

kubectl apply -f "$SCRIPT_DIR/region1-api-lb.yaml" --context $REGION1_CONTEXT
echo -e "${GREEN}✅ Region 1 LoadBalancer service created${NC}"
echo ""

# Create LoadBalancer service for Region 2 REC API
echo -e "${BLUE}🔧 Creating LoadBalancer service for Region 2 REC API...${NC}"
cat > "$SCRIPT_DIR/region2-api-lb.yaml" <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${REGION2_REC_NAME}-api-lb
  namespace: $NAMESPACE
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
spec:
  type: LoadBalancer
  selector:
    app: redis-enterprise
    redis.io/cluster: $REGION2_REC_NAME
  ports:
    - name: api
      port: 9443
      targetPort: 9443
      protocol: TCP
EOF

kubectl apply -f "$SCRIPT_DIR/region2-api-lb.yaml" --context $REGION2_CONTEXT
echo -e "${GREEN}✅ Region 2 LoadBalancer service created${NC}"
echo ""

# Wait for LoadBalancers to be provisioned
echo -e "${YELLOW}⏳ Waiting for LoadBalancers to be provisioned (this may take 2-3 minutes)...${NC}"
echo ""

for i in {1..60}; do
    REC1_LB=$(kubectl get svc ${REGION1_REC_NAME}-api-lb -n $NAMESPACE --context $REGION1_CONTEXT -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    REC2_LB=$(kubectl get svc ${REGION2_REC_NAME}-api-lb -n $NAMESPACE --context $REGION2_CONTEXT -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [ -n "$REC1_LB" ] && [ -n "$REC2_LB" ]; then
        echo -e "${GREEN}✅ LoadBalancers provisioned!${NC}"
        echo ""
        echo "  Region 1 API LB: $REC1_LB"
        echo "  Region 2 API LB: $REC2_LB"
        echo ""
        echo -e "${GREEN}✅ LoadBalancer services ready${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Update RERC resources to use these LoadBalancer endpoints"
        echo "  2. Run ./deploy-crdb.sh to create the Active-Active database"
        echo ""
        exit 0
    fi
    
    echo -n "."
    sleep 3
done

echo ""
echo -e "${RED}❌ Timeout waiting for LoadBalancers${NC}"
echo "Check the services manually:"
echo "  kubectl get svc -n $NAMESPACE --context $REGION1_CONTEXT"
echo "  kubectl get svc -n $NAMESPACE --context $REGION2_CONTEXT"
exit 1

