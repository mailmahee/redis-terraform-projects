#!/bin/bash
#==============================================================================
# REDIS ENTERPRISE MONITORING UI DEPLOYMENT SCRIPT
#==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yaml"
ENV_CONFIG="$SCRIPT_DIR/../config.env"

echo ""
echo "=========================================================================="
echo "  Redis Monitoring UI Deployment"
echo "=========================================================================="
echo ""

# Load configuration from config.env
if [ ! -f "$ENV_CONFIG" ]; then
    echo -e "${RED}❌ ERROR: config.env not found${NC}"
    echo "Please run 'terraform apply' first to generate this file."
    exit 1
fi

echo -e "${BLUE}📋 Loading configuration from config.env...${NC}"
source "$ENV_CONFIG"

# Load user preferences from config.yaml
DEPLOYMENT_REGION=$(yq eval '.deployment_region' "$CONFIG_FILE" 2>/dev/null || echo "region1")
REFRESH_INTERVAL=$(yq eval '.refresh_interval' "$CONFIG_FILE" 2>/dev/null || echo "5")

echo -e "${GREEN}✅ Configuration loaded${NC}"
echo ""
echo "Configuration:"
echo "  Project: $PROJECT_PREFIX"
echo "  Region 1: $AWS_REGION1 (Context: $REGION1_CONTEXT)"
echo "  Region 2: $AWS_REGION2 (Context: $REGION2_CONTEXT)"
echo "  Namespace: $NAMESPACE"
echo "  CRDB Name: $CRDB_NAME"
echo "  Deployment Region: $DEPLOYMENT_REGION"
echo ""

# Auto-detect database name from kubectl
echo -e "${BLUE}🔍 Auto-detecting database...${NC}"
DATABASE_NAME=$(kubectl get reaadb -n "$NAMESPACE" --context "$REGION1_CONTEXT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "$CRDB_NAME")

if [ -z "$DATABASE_NAME" ]; then
    echo -e "${YELLOW}⚠️  No REAADB found. Using configured name: $CRDB_NAME${NC}"
    DATABASE_NAME="$CRDB_NAME"
else
    echo -e "${GREEN}✅ Detected database: $DATABASE_NAME${NC}"
fi

# Auto-detect secret names from kubectl
echo ""
echo -e "${BLUE}🔍 Auto-detecting secret names...${NC}"
SECRET_R1=$(kubectl get secret -n "$NAMESPACE" --context "$REGION1_CONTEXT" -o name | grep "^secret/$REGION1_REC_NAME" | head -1 | cut -d'/' -f2 2>/dev/null || echo "$REGION1_REC_NAME")
SECRET_R2=$(kubectl get secret -n "$NAMESPACE" --context "$REGION2_CONTEXT" -o name | grep "^secret/$REGION2_REC_NAME" | head -1 | cut -d'/' -f2 2>/dev/null || echo "$REGION2_REC_NAME")

echo -e "${GREEN}✅ Region 1 secret: $SECRET_R1${NC}"
echo -e "${GREEN}✅ Region 2 secret: $SECRET_R2${NC}"
echo ""

# Set deployment context based on user choice
if [ "$DEPLOYMENT_REGION" = "region1" ]; then
    DEPLOY_CONTEXT="$REGION1_CONTEXT"
    DEPLOY_REGION_NAME="$AWS_REGION1"
    API_FQDN_R1="api.region1.${INGRESS_DOMAIN}"
    API_FQDN_R2="api.region2.${INGRESS_DOMAIN}"
elif [ "$DEPLOYMENT_REGION" = "region2" ]; then
    DEPLOY_CONTEXT="$REGION2_CONTEXT"
    DEPLOY_REGION_NAME="$AWS_REGION2"
    API_FQDN_R1="api.region1.${INGRESS_DOMAIN}"
    API_FQDN_R2="api.region2.${INGRESS_DOMAIN}"
else
    echo -e "${RED}❌ Invalid deployment_region: $DEPLOYMENT_REGION${NC}"
    echo "   Must be 'region1' or 'region2'"
    exit 1
fi

echo -e "${BLUE}📦 Deployment Configuration:${NC}"
echo "  Deployment Region: $DEPLOYMENT_REGION ($DEPLOY_REGION_NAME)"
echo "  Namespace: $NAMESPACE"
echo "  Context: $DEPLOY_CONTEXT"
echo "  Database: $DATABASE_NAME"
echo "  Refresh Interval: ${REFRESH_INTERVAL}s"
echo ""

# Generate dynamic configuration for the app
echo -e "${BLUE}📝 Generating auto-config.yaml...${NC}"

cat > "$SCRIPT_DIR/auto-config.yaml" <<EOF
# Auto-generated configuration from config.env
# DO NOT EDIT - regenerated on each deployment

deployment_region: $DEPLOYMENT_REGION
namespace: $NAMESPACE
refresh_interval: $REFRESH_INTERVAL
database_name: $DATABASE_NAME

regions:
  region1:
    name: $AWS_REGION1
    api_endpoint: $API_FQDN_R1
    api_port: 9443
    secret_name: $SECRET_R1
    context: $REGION1_CONTEXT

  region2:
    name: $AWS_REGION2
    api_endpoint: $API_FQDN_R2
    api_port: 9443
    secret_name: $SECRET_R2
    context: $REGION2_CONTEXT

resources:
  requests:
    cpu: $(yq eval '.resources.requests.cpu' "$CONFIG_FILE" 2>/dev/null || echo "250m")
    memory: $(yq eval '.resources.requests.memory' "$CONFIG_FILE" 2>/dev/null || echo "256Mi")
  limits:
    cpu: $(yq eval '.resources.limits.cpu' "$CONFIG_FILE" 2>/dev/null || echo "500m")
    memory: $(yq eval '.resources.limits.memory' "$CONFIG_FILE" 2>/dev/null || echo "512Mi")
EOF

echo -e "${GREEN}✅ Generated auto-config.yaml${NC}"
echo ""

# Verify context exists
echo -e "${BLUE}🔍 Verifying deployment prerequisites...${NC}"
if ! kubectl config get-contexts $DEPLOY_CONTEXT &> /dev/null; then
    echo -e "${RED}❌ Error: Context '$DEPLOY_CONTEXT' not found${NC}"
    echo "Available contexts:"
    kubectl config get-contexts
    exit 1
fi

# Verify namespace exists
if ! kubectl get namespace $NAMESPACE --context $DEPLOY_CONTEXT &> /dev/null; then
    echo -e "${RED}❌ Error: Namespace '$NAMESPACE' not found in context '$DEPLOY_CONTEXT'${NC}"
    exit 1
fi

# Verify secrets exist
if ! kubectl get secret $SECRET_R1 -n $NAMESPACE --context $REGION1_CONTEXT &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Secret '$SECRET_R1' not found in region 1${NC}"
fi
if ! kubectl get secret $SECRET_R2 -n $NAMESPACE --context $REGION2_CONTEXT &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: Secret '$SECRET_R2' not found in region 2${NC}"
fi
echo -e "${GREEN}✅ Prerequisites verified${NC}"
echo ""

# Create ConfigMap for app code
echo -e "${BLUE}📦 Creating ConfigMaps...${NC}"
kubectl create configmap redis-monitoring-ui-code \
    --from-file=app.py=app/app.py \
    --namespace=$NAMESPACE \
    --context=$DEPLOY_CONTEXT \
    --dry-run=client -o yaml | kubectl apply -f - --context=$DEPLOY_CONTEXT

# Create ConfigMap for HTML template
kubectl create configmap redis-monitoring-ui-templates \
    --from-file=index.html=app/templates/index.html \
    --namespace=$NAMESPACE \
    --context=$DEPLOY_CONTEXT \
    --dry-run=client -o yaml | kubectl apply -f - --context=$DEPLOY_CONTEXT

# Create ConfigMap for config
kubectl create configmap redis-monitoring-ui-config \
    --from-file=config.yaml=auto-config.yaml \
    --namespace=$NAMESPACE \
    --context=$DEPLOY_CONTEXT \
    --dry-run=client -o yaml | kubectl apply -f - --context=$DEPLOY_CONTEXT

echo -e "${GREEN}✅ ConfigMaps created${NC}"
echo ""

# Deploy RBAC
echo -e "${BLUE}🔐 Deploying RBAC...${NC}"
kubectl apply -f k8s/rbac.yaml --context=$DEPLOY_CONTEXT
echo -e "${GREEN}✅ RBAC deployed${NC}"
echo ""

# Deploy Service
echo -e "${BLUE}🌐 Deploying Service...${NC}"
kubectl apply -f k8s/service.yaml --context=$DEPLOY_CONTEXT
echo -e "${GREEN}✅ Service deployed${NC}"
echo ""

# Deploy Deployment
echo -e "${BLUE}🚀 Deploying application...${NC}"
kubectl apply -f k8s/deployment.yaml --context=$DEPLOY_CONTEXT
echo -e "${GREEN}✅ Deployment created${NC}"
echo ""

# Wait for deployment
echo -e "${YELLOW}⏳ Waiting for deployment to be ready...${NC}"
kubectl rollout status deployment/redis-monitoring-ui -n $NAMESPACE --context=$DEPLOY_CONTEXT --timeout=120s

echo ""
echo "=========================================================================="
echo -e "${GREEN}✅ Redis Monitoring UI Deployed Successfully!${NC}"
echo "=========================================================================="
echo ""
echo "Access the UI:"
echo "  kubectl port-forward -n $NAMESPACE svc/redis-monitoring-ui 8080:5000 --context $DEPLOY_CONTEXT"
echo ""
echo "Then open: http://localhost:8080"
echo ""
echo "View logs:"
echo "  kubectl logs -n $NAMESPACE -l app=redis-monitoring-ui --tail=100 -f --context $DEPLOY_CONTEXT"
echo ""
echo "=========================================================================="
echo ""
