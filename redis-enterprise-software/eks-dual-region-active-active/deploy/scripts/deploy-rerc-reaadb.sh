#!/bin/bash
# =============================================================================
# DEPLOY RERC AND REAADB - SIMPLIFIED VERSION
# =============================================================================
# Uses Terraform-generated manifests (no generation logic needed)
# Applies them with proper wait times and verification
# =============================================================================

# =============================================================================
# STEP 1: DEPLOY LOCAL RERCs
# =============================================================================

echo "========================================================================="
echo "STEP 1: Deploy Local RERCs"
echo "========================================================================="
echo ""
echo "Deploying local RERC to Region 1..."
kubectl apply -f "${GENERATED_DIR}/rerc-region1-local.yaml" --context ${REGION1_CONTEXT}

echo ""
echo "Deploying local RERC to Region 2..."
kubectl apply -f "${GENERATED_DIR}/rerc-region2-local.yaml" --context ${REGION2_CONTEXT}

echo ""
echo "✓ Local RERCs deployed"
echo ""
echo "Waiting 30 seconds for local RERCs to initialize..."
sleep 30

# Verify local RERCs
echo ""
echo "Verifying local RERCs..."
echo ""
echo "Region 1 RERCs:"
kubectl get rerc -n ${NAMESPACE} --context ${REGION1_CONTEXT} || true
echo ""
echo "Region 2 RERCs:"
kubectl get rerc -n ${NAMESPACE} --context ${REGION2_CONTEXT} || true
echo ""

# =============================================================================
# STEP 2: DEPLOY REMOTE RERCs
# =============================================================================

echo "========================================================================="
echo "STEP 2: Deploy Remote RERCs"
echo "========================================================================="
echo ""
read -p "Continue with remote RERC deployment? (yes/no) " -r
echo ""
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Deployment paused. Run this script again to continue."
    exit 0
fi

echo "Deploying remote RERC to Region 1 (points to Region 2)..."
kubectl apply -f "${GENERATED_DIR}/rerc-region1-remote.yaml" --context ${REGION1_CONTEXT}

echo ""
echo "Deploying remote RERC to Region 2 (points to Region 1)..."
kubectl apply -f "${GENERATED_DIR}/rerc-region2-remote.yaml" --context ${REGION2_CONTEXT}

echo ""
echo "✓ Remote RERCs deployed"
echo ""
echo "Waiting 30 seconds for remote RERCs to establish connections..."
sleep 30

# Verify all RERCs
echo ""
echo "Verifying all RERCs..."
echo ""
echo "Region 1 RERCs:"
kubectl get rerc -n ${NAMESPACE} --context ${REGION1_CONTEXT}
echo ""
echo "Region 2 RERCs:"
kubectl get rerc -n ${NAMESPACE} --context ${REGION2_CONTEXT}
echo ""

# =============================================================================
# STEP 3: DEPLOY REAADB
# =============================================================================

echo "========================================================================="
echo "STEP 3: Deploy Active-Active Database (REAADB)"
echo "========================================================================="
echo ""
echo "⚠️  IMPORTANT: Verify that all RERCs show 'Active' status above"
echo ""
read -p "Deploy REAADB? (yes/no) " -r
echo ""
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Deployment paused. Run this script again to continue."
    exit 0
fi

echo "Deploying REAADB to Region 1..."
kubectl apply -f "${GENERATED_DIR}/reaadb.yaml" --context ${REGION1_CONTEXT}

echo ""
echo "✓ REAADB deployed"
echo ""
echo "Waiting 120 seconds for REAADB to initialize..."
sleep 120

# =============================================================================
# STEP 4: VERIFY DEPLOYMENT
# =============================================================================

echo ""
echo "========================================================================="
echo "STEP 4: Verify Deployment"
echo "========================================================================="
echo ""

echo "Region 1 Resources:"
echo "-------------------"
kubectl get rerc,reaadb -n ${NAMESPACE} --context ${REGION1_CONTEXT}

echo ""
echo "Region 2 Resources:"
echo "-------------------"
kubectl get rerc,reaadb -n ${NAMESPACE} --context ${REGION2_CONTEXT}

echo ""
echo "========================================================================="
echo "Deployment Complete!"
echo "========================================================================="
echo ""
echo "Next steps:"
echo "  1. Verify REAADB status: kubectl describe reaadb -n ${NAMESPACE} --context ${REGION1_CONTEXT}"
echo "  2. Get database endpoint: kubectl get reaadb -n ${NAMESPACE} -o yaml --context ${REGION1_CONTEXT}"
echo "  3. Test connectivity from both regions"
echo ""
echo "Troubleshooting:"
echo "  - If REAADB is pending, check: kubectl describe reaadb -n ${NAMESPACE} --context ${REGION1_CONTEXT}"
echo "  - Verify RERC status: kubectl get rerc -n ${NAMESPACE} --context ${REGION1_CONTEXT}"
echo "  - Check operator logs: kubectl logs -l name=redis-enterprise-operator -n ${NAMESPACE} --context ${REGION1_CONTEXT}"
echo ""
