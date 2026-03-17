#!/bin/bash
#==============================================================================
# REDIS ENTERPRISE MONITORING UI CLEANUP SCRIPT
#==============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load configuration
CONFIG_FILE="config.yaml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: config.yaml not found${NC}"
    exit 1
fi

DEPLOYMENT_REGION=$(grep "deployment_region:" $CONFIG_FILE | awk '{print $2}')
NAMESPACE=$(grep "namespace:" $CONFIG_FILE | awk '{print $2}')

if [ "$DEPLOYMENT_REGION" == "region1" ]; then
    CONTEXT="region1-new"
elif [ "$DEPLOYMENT_REGION" == "region2" ]; then
    CONTEXT="region2-new"
else
    echo -e "${RED}Error: Invalid deployment_region in config.yaml${NC}"
    exit 1
fi

echo -e "${YELLOW}Removing Redis Enterprise Monitoring UI...${NC}"

kubectl delete -f k8s/deployment.yaml --context=$CONTEXT --ignore-not-found=true
kubectl delete -f k8s/service.yaml --context=$CONTEXT --ignore-not-found=true
kubectl delete -f k8s/rbac.yaml --context=$CONTEXT --ignore-not-found=true

kubectl delete configmap redis-monitoring-ui-code -n $NAMESPACE --context=$CONTEXT --ignore-not-found=true
kubectl delete configmap redis-monitoring-ui-templates -n $NAMESPACE --context=$CONTEXT --ignore-not-found=true
kubectl delete configmap redis-monitoring-ui-config -n $NAMESPACE --context=$CONTEXT --ignore-not-found=true

echo -e "${GREEN}✓ Cleanup complete${NC}"