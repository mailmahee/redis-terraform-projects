#!/bin/bash
# Master orchestration script for complete Active-Active deployment
# Usage: ./deploy-all.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration files
VALUES_REGION1="$DEPLOY_DIR/values-region1.yaml"
VALUES_REGION2="$DEPLOY_DIR/values-region2.yaml"

# Load DNS configuration from values
HOSTED_ZONE_ID=$(yq eval '.dns.hostedZoneId' "$VALUES_REGION1")

echo "=========================================="
echo "Redis Enterprise Active-Active Deployment"
echo "=========================================="
echo "This script will deploy a complete Active-Active Redis Enterprise"
echo "cluster across two AWS regions with full validation at each step."
echo ""
echo "Configuration:"
echo "  - Region 1 values: $VALUES_REGION1"
echo "  - Region 2 values: $VALUES_REGION2"
echo "  - DNS Hosted Zone: $HOSTED_ZONE_ID"
echo ""
echo "Starting automated deployment..."
echo ""

# Step 1: Verify Terraform is deployed
echo "=========================================="
echo "STEP 1: Verify Terraform Infrastructure"
echo "=========================================="
echo ""

cd "$DEPLOY_DIR/.."
if [ ! -f "terraform.tfstate" ]; then
  echo "✗ ERROR: terraform.tfstate not found"
  echo "  Please run 'terraform apply' first"
  exit 1
fi

echo "Checking Terraform state..."
RESOURCE_COUNT=$(terraform show -json 2>/dev/null | jq '.values.root_module.resources | length' 2>/dev/null || echo "0")
if [ "$RESOURCE_COUNT" == "0" ]; then
  echo "✗ ERROR: No resources found in Terraform state"
  echo "  Please run 'terraform apply' first"
  exit 1
fi

echo "✓ Terraform infrastructure deployed ($RESOURCE_COUNT resources)"
echo ""

# Step 2: Configure kubectl contexts
echo "=========================================="
echo "STEP 2: Configure kubectl Contexts"
echo "=========================================="
echo ""

REGION1=$(yq eval '.cluster.region' "$VALUES_REGION1")
REGION2=$(yq eval '.cluster.region' "$VALUES_REGION2")
EKS_CLUSTER_R1=$(yq eval '.cluster.eksClusterName' "$VALUES_REGION1")
EKS_CLUSTER_R2=$(yq eval '.cluster.eksClusterName' "$VALUES_REGION2")
K8S_CONTEXT_R1=$(yq eval '.cluster.k8s_context' "$VALUES_REGION1")
K8S_CONTEXT_R2=$(yq eval '.cluster.k8s_context' "$VALUES_REGION2")

echo "Configuring kubectl for Region 1..."
aws eks update-kubeconfig --region "$REGION1" --name "$EKS_CLUSTER_R1" --alias "$K8S_CONTEXT_R1" &>/dev/null
echo "✓ Context configured: $K8S_CONTEXT_R1"

echo "Configuring kubectl for Region 2..."
aws eks update-kubeconfig --region "$REGION2" --name "$EKS_CLUSTER_R2" --alias "$K8S_CONTEXT_R2" &>/dev/null
echo "✓ Context configured: $K8S_CONTEXT_R2"
echo ""

# Step 3: Wait for and validate RECs
echo "=========================================="
echo "STEP 3: Validate Redis Enterprise Clusters"
echo "=========================================="
echo ""

echo "Waiting for RECs to be ready (this may take several minutes)..."
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/validate-rec.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/validate-rec.sh" "$VALUES_REGION2"

echo "✓ Both RECs are Running with proper configuration"
echo ""

# Step 4: Setup admission controllers
echo "=========================================="
echo "STEP 4: Setup Admission Controllers"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/setup-admission.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/setup-admission.sh" "$VALUES_REGION2"

echo "✓ Admission controllers configured"
echo ""

# Step 5: Validate ingress resources
echo "=========================================="
echo "STEP 5: Validate Ingress Resources"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/validate-ingress.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/validate-ingress.sh" "$VALUES_REGION2"

echo "✓ Ingress resources validated"
echo ""

# Step 6: Create DNS records for API and database endpoints
echo "=========================================="
echo "STEP 6: Create DNS Records for API Endpoints"
echo "=========================================="
echo ""

echo "Creating DNS records for API endpoints..."
echo "Note: Database endpoint DNS records will be created after REAADB deployment"
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/validate-dns.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/validate-dns.sh" "$VALUES_REGION2"

echo "✓ API DNS records validated"
echo ""

# Step 7: Deploy RERCs
echo "=========================================="
echo "STEP 7: Deploy Remote Cluster References (RERCs)"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/deploy-rerc.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/deploy-rerc.sh" "$VALUES_REGION2"

echo "Waiting for RERCs to become Active..."
sleep 10
echo ""

# Step 8: Validate RERCs
echo "=========================================="
echo "STEP 8: Validate RERCs"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/validate-rerc.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/validate-rerc.sh" "$VALUES_REGION2"

echo "✓ RERCs validated (local/remote status correct)"
echo ""

# Step 9: Deploy REAADB
echo "=========================================="
echo "STEP 9: Deploy Active-Active Database (REAADB)"
echo "=========================================="
echo ""

echo "Deploying REAADB from Region 1..."
bash "$SCRIPT_DIR/deploy-reaadb.sh" "$VALUES_REGION1"

echo "Waiting for REAADB to become active..."
sleep 15
echo ""

# Step 10: Create DNS records for database endpoints
echo "=========================================="
echo "STEP 10: Create DNS Records for Database Endpoints"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/create-dns-records.sh" "$VALUES_REGION1" "$HOSTED_ZONE_ID"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/create-dns-records.sh" "$VALUES_REGION2" "$HOSTED_ZONE_ID"

echo "Waiting for DNS propagation..."
sleep 30
echo ""

# Step 11: Validate REAADB
echo "=========================================="
echo "STEP 11: Validate REAADB"
echo "=========================================="
echo ""

echo "--- Region 1 ---"
bash "$SCRIPT_DIR/validate-reaadb.sh" "$VALUES_REGION1"

echo "--- Region 2 ---"
bash "$SCRIPT_DIR/validate-reaadb.sh" "$VALUES_REGION2"

echo "✓ REAADB validated in both regions"
echo ""

# Step 12: Test bidirectional replication
echo "=========================================="
echo "STEP 12: Test Bidirectional Replication"
echo "=========================================="
echo ""

bash "$SCRIPT_DIR/validate-replication.sh" "$VALUES_REGION1" "$VALUES_REGION2"

echo ""
echo "=========================================="
echo "✓ DEPLOYMENT COMPLETE!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Terraform infrastructure deployed"
echo "  ✓ kubectl contexts configured"
echo "  ✓ Redis Enterprise Clusters running in both regions"
echo "  ✓ Admission controllers configured"
echo "  ✓ Ingress resources validated"
echo "  ✓ API DNS records validated"
echo "  ✓ RERCs deployed and validated"
echo "  ✓ REAADB deployed and active"
echo "  ✓ Database DNS records created"
echo "  ✓ Bidirectional replication working"
echo ""
echo "Your Active-Active Redis Enterprise deployment is fully operational!"
echo ""
echo "Next steps:"
echo "  - Access Region 1 REC: kubectl --context=$(yq eval '.cluster.k8s_context' "$VALUES_REGION1") -n redis-enterprise get rec"
echo "  - Access Region 2 REC: kubectl --context=$(yq eval '.cluster.k8s_context' "$VALUES_REGION2") -n redis-enterprise get rec"
echo "  - View REAADB: kubectl --context=$(yq eval '.cluster.k8s_context' "$VALUES_REGION1") -n redis-enterprise get reaadb"
echo ""

