#!/usr/bin/env bash
#==============================================================================
# REDIS ENTERPRISE ACTIVE-ACTIVE DEPLOYMENT SCRIPT
#==============================================================================
# Deploys two EKS clusters with Redis Enterprise and an Active-Active database.
#
# Why two phases?
# Terraform's kubernetes/helm/kubectl providers need EKS endpoints to
# initialize. Those endpoints only exist after EKS is created. Phase 1 creates
# the EKS clusters and Redis Enterprise clusters. Phase 2 finishes everything
# else (VPC peering, DNS, RERC, REAADB).
#
# Usage:
#   ./deploy.sh              # interactive (prompts before each phase)
#   ./deploy.sh --auto       # non-interactive (no prompts, for CI)
#   ./deploy.sh --destroy    # destroy all resources
#==============================================================================

set -euo pipefail

#==============================================================================
# CONFIGURATION
#==============================================================================

AUTO=false
DESTROY=false

for arg in "$@"; do
  case $arg in
    --auto)    AUTO=true ;;
    --destroy) DESTROY=true ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: $0 [--auto] [--destroy]"
      exit 1
      ;;
  esac
done

#==============================================================================
# HELPERS
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

confirm() {
  if [ "$AUTO" = true ]; then
    info "Auto mode: proceeding with: $*"
    return 0
  fi
  echo ""
  read -rp "$(echo -e "${YELLOW}Proceed with: $* ? [y/N]${NC} ")" ans
  [[ "$ans" =~ ^[Yy]$ ]] || { info "Aborted."; exit 0; }
}

#==============================================================================
# PRE-FLIGHT CHECKS
#==============================================================================

info "Checking prerequisites..."

command -v terraform >/dev/null 2>&1 || error "terraform not found in PATH"
command -v aws       >/dev/null 2>&1 || error "aws CLI not found in PATH"
command -v kubectl   >/dev/null 2>&1 || error "kubectl not found in PATH"
command -v curl      >/dev/null 2>&1 || error "curl not found in PATH"

if [ ! -f "terraform.tfvars" ]; then
  error "terraform.tfvars not found. Copy terraform.tfvars.example and fill in your values."
fi

if [ ! -d ".terraform" ]; then
  info "Running terraform init..."
  terraform init
fi

AWS_IDENTITY=$(aws sts get-caller-identity 2>&1) || error "AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE."
success "AWS identity: $(echo "$AWS_IDENTITY" | grep -o '"Arn": "[^"]*"' | head -1)"

#==============================================================================
# DESTROY MODE
#==============================================================================

if [ "$DESTROY" = true ]; then
  warn "DESTROY MODE — this will delete all resources including EKS clusters!"
  confirm "terraform destroy"
  terraform destroy ${AUTO:+-auto-approve}
  success "All resources destroyed."
  exit 0
fi

#==============================================================================
# PHASE 1: EKS CLUSTERS + REDIS ENTERPRISE CLUSTERS
#==============================================================================
# Creates the AWS infrastructure (VPC, EKS, node groups) and deploys the Redis
# Enterprise operator and cluster in each region.
#
# The kubernetes/helm/kubectl providers can't initialize until EKS endpoints
# are known, which is why this phase runs first with -target to create only
# the resources that don't need those providers.
#==============================================================================

echo ""
echo "======================================================================"
echo "  PHASE 1: EKS Clusters + Redis Enterprise Clusters"
echo "======================================================================"
echo "  Creates: VPC, EKS, node groups, Redis operator, REC (both regions)"
echo "  Time: ~15-20 minutes"
echo "======================================================================"

confirm "terraform apply (Phase 1 — EKS + Redis clusters)"

terraform apply \
  -target=module.redis_cluster_region1 \
  -target=module.redis_cluster_region2 \
  ${AUTO:+-auto-approve}

success "Phase 1 complete — EKS clusters and Redis Enterprise clusters are up."

#==============================================================================
# PHASE 2: FULL DEPLOYMENT
#==============================================================================
# Now that EKS endpoints are known, Terraform can configure the kubernetes,
# helm, and kubectl providers and deploy the remaining resources:
#   - VPC peering mesh
#   - DNS records (Route53 CNAME → NLB)
#   - RERC credentials exchange
#   - RERC CRDs (both regions)
#   - REAADB (Active-Active database)
#==============================================================================

echo ""
echo "======================================================================"
echo "  PHASE 2: VPC Peering + DNS + RERC + REAADB"
echo "======================================================================"
echo "  Creates: VPC peering, DNS records, RERC, Active-Active database"
echo "  Time: ~10-15 minutes"
echo "======================================================================"

confirm "terraform apply (Phase 2 — full deployment)"

terraform apply ${AUTO:+-auto-approve}

#==============================================================================
# COMPLETION
#==============================================================================

echo ""
echo "======================================================================"
success "Deployment complete!"
echo "======================================================================"

REGIONS=$(terraform output -json regions_deployed 2>/dev/null | tr -d '"[]' || echo "see terraform output")
info "Regions: $REGIONS"

echo ""
info "Verify deployment:"
echo "  terraform output"
echo ""
info "Check Active-Active status:"
REGION1=$(terraform output -json 2>/dev/null | python3 -c "import json,sys; o=json.load(sys.stdin); print(list(o.get('region1_info',{}).get('value',{}).keys())[0])" 2>/dev/null || echo "us-west-2")
echo "  aws eks update-kubeconfig --region \$REGION1 --name \$(terraform output -raw eks_cluster_name_region1 2>/dev/null || echo '<cluster>')"
echo "  kubectl get rec,rerc,reaadb -n redis-enterprise"
echo ""
warn "Remember: run 'terraform destroy' or './deploy.sh --destroy' when done to avoid ongoing costs."
