#!/bin/bash
#==============================================================================
# REDIS FLEX DEPLOYMENT SCRIPT FOR AWS EKS
#==============================================================================
# This script automates the deployment of Redis Enterprise with Redis Flex
# on Amazon EKS.
#
# Prerequisites:
# 1. terraform.tfvars configured with your values
# 2. AWS credentials configured (aws configure)
# 3. kubectl, terraform, and aws CLI installed
#
# Usage:
#   chmod +x deploy-redis-flex.sh
#   ./deploy-redis-flex.sh
#==============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check terraform
    if ! command -v terraform &> /dev/null; then
        log_error "terraform not found. Please install: https://www.terraform.io/downloads"
        exit 1
    fi

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found. Please install: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Check aws CLI
    if ! command -v aws &> /dev/null; then
        log_error "aws CLI not found. Please install: https://aws.amazon.com/cli/"
        exit 1
    fi

    # Check terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        log_error "terraform.tfvars not found. Please copy from terraform.tfvars.example and configure."
        echo ""
        echo "Run: cp terraform.tfvars.example terraform.tfvars"
        echo "Then edit terraform.tfvars with your values."
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."

    # Initialize Terraform
    log_info "Running terraform init..."
    terraform init

    # Plan
    log_info "Running terraform plan..."
    terraform plan -out=tfplan

    # Ask for confirmation
    echo ""
    read -p "Do you want to proceed with terraform apply? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi

    # Apply
    log_info "Running terraform apply (this takes ~15-20 minutes)..."
    terraform apply tfplan

    log_success "Infrastructure deployed successfully"
}

# Configure kubectl
configure_kubectl() {
    log_info "Configuring kubectl..."

    # Extract cluster name from terraform output
    CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
    AWS_REGION=$(terraform output -raw region 2>/dev/null || echo "us-west-2")

    if [ -z "$CLUSTER_NAME" ]; then
        log_warning "Could not get cluster name from terraform output"
        read -p "Enter your cluster name (e.g., your-name-redis-ent-eks): " CLUSTER_NAME
    fi

    log_info "Updating kubeconfig for cluster: $CLUSTER_NAME in region: $AWS_REGION"
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

    # Verify cluster access
    log_info "Verifying cluster access..."
    kubectl get nodes

    log_success "kubectl configured successfully"
}

# Deploy local storage provisioner
deploy_storage_provisioner() {
    log_info "Deploying local NVMe storage provisioner..."

    kubectl apply -f k8s-manifests/local-storage-provisioner.yaml

    log_info "Waiting for provisioner pods to start (30 seconds)..."
    sleep 30

    # Check provisioner pods
    log_info "Checking provisioner pod status..."
    kubectl get pods -n local-storage -l app=local-volume-provisioner

    # Wait for PVs to be created
    log_info "Waiting for NVMe devices to be discovered and provisioned (30 seconds)..."
    sleep 30

    # Check PVs
    log_info "Checking for local-scsi PersistentVolumes..."
    PV_COUNT=$(kubectl get pv | grep local-scsi | wc -l)

    if [ "$PV_COUNT" -eq 0 ]; then
        log_error "No local-scsi PVs found. NVMe devices may not be available."
        log_error "Ensure you are using i3.xlarge or i4i.xlarge instance types."
        log_info "Check logs with: kubectl logs -n local-storage -l app=local-volume-provisioner"
        exit 1
    fi

    log_success "Local storage provisioner deployed successfully ($PV_COUNT PVs created)"
}

# Wait for Redis Enterprise cluster
wait_for_redis_cluster() {
    log_info "Waiting for Redis Enterprise cluster to be ready..."

    # Wait up to 10 minutes
    TIMEOUT=600
    ELAPSED=0
    INTERVAL=15

    while [ $ELAPSED -lt $TIMEOUT ]; do
        STATE=$(kubectl get rec redis-ent-eks -n redis-enterprise -o jsonpath='{.status.state}' 2>/dev/null || echo "NotFound")

        if [ "$STATE" = "Running" ]; then
            log_success "Redis Enterprise cluster is running!"
            break
        fi

        log_info "Cluster state: $STATE (waiting...)"
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
    done

    if [ "$STATE" != "Running" ]; then
        log_error "Cluster did not become ready within $TIMEOUT seconds"
        log_error "Current state: $STATE"
        log_info "Check with: kubectl describe rec redis-ent-eks -n redis-enterprise"
        exit 1
    fi

    # Verify Redis Flex is enabled
    log_info "Verifying Redis Flex is enabled..."
    kubectl describe rec redis-ent-eks -n redis-enterprise | grep -A 10 "Redis On Flash" || {
        log_warning "Redis Flex configuration not found in cluster"
    }

    # Check sample database
    log_info "Checking sample database status..."
    kubectl get redb -n redis-enterprise

    log_success "Redis Enterprise cluster ready"
}

# Display access instructions
show_access_instructions() {
    echo ""
    echo "=========================================================================="
    echo "  DEPLOYMENT COMPLETE!"
    echo "=========================================================================="
    echo ""
    echo "Your Redis Enterprise cluster with Redis Flex is ready."
    echo ""
    echo "📊 Cluster Information:"
    kubectl get rec -n redis-enterprise
    echo ""
    echo "💾 Databases:"
    kubectl get redb -n redis-enterprise
    echo ""
    echo "🔧 Access Redis Enterprise UI:"
    echo "   Terminal 1: kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443"
    echo "   Browser:    https://localhost:8443"
    echo "   Username:   admin@admin.com"
    echo "   Password:   (your configured password)"
    echo ""
    echo "💻 Access Sample Database:"
    echo "   Terminal 2: kubectl port-forward -n redis-enterprise svc/demo 12000:12000"
    echo "   Terminal 3: redis-cli -h localhost -p 12000 -a admin"
    echo ""
    echo "📈 Deploy Large Redis Flex Database (35GB):"
    echo "   kubectl apply -f max-db-password.yaml"
    echo "   kubectl apply -f max-memory-db.yaml"
    echo ""
    echo "📖 For detailed instructions, see REDIS-FLEX-DEPLOYMENT.md"
    echo ""
    echo "=========================================================================="
}

# Main execution
main() {
    echo "=========================================================================="
    echo "  Redis Flex Deployment for AWS EKS"
    echo "=========================================================================="
    echo ""

    check_prerequisites
    deploy_infrastructure
    configure_kubectl
    deploy_storage_provisioner
    wait_for_redis_cluster
    show_access_instructions

    log_success "Deployment completed successfully!"
}

# Run main function
main
