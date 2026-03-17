#!/bin/bash

#==============================================================================
# PROMETHEUS MONITORING DEPLOYMENT SCRIPT
#==============================================================================
# This script deploys Prometheus monitoring for Redis Enterprise
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
echo "  Prometheus Monitoring Deployment"
echo "=========================================================================="
echo ""

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: config.env not found${NC}"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${BLUE}📋 Configuration loaded${NC}"
echo "  Namespace: $NAMESPACE"
echo "  Region 1 Context: $REGION1_CONTEXT"
echo "  Region 2 Context: $REGION2_CONTEXT"
echo ""

# Deploy ServiceMonitor for Region 1
echo -e "${BLUE}🚀 Deploying ServiceMonitor for Region 1...${NC}"
kubectl apply -f servicemonitor.yaml --context $REGION1_CONTEXT

# Deploy ServiceMonitor for Region 2
echo -e "${BLUE}🚀 Deploying ServiceMonitor for Region 2...${NC}"
kubectl apply -f servicemonitor.yaml --context $REGION2_CONTEXT

# Deploy Prometheus Rules
echo -e "${BLUE}🚀 Deploying Prometheus Rules...${NC}"
kubectl apply -f prometheus-rules.yaml --context $REGION1_CONTEXT
kubectl apply -f prometheus-rules.yaml --context $REGION2_CONTEXT

echo ""
echo "=========================================================================="
echo -e "${GREEN}✅ Prometheus Monitoring Deployed!${NC}"
echo "=========================================================================="
echo ""
echo "Verification:"
echo "  kubectl get servicemonitor -n $NAMESPACE --context $REGION1_CONTEXT"
echo "  kubectl get servicemonitor -n $NAMESPACE --context $REGION2_CONTEXT"
echo ""

