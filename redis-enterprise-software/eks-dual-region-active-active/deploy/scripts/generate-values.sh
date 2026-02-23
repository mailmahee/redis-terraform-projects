#!/bin/bash
# Generate values files from Terraform outputs
# Usage: ./generate-values.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$(dirname "$DEPLOY_DIR")"

echo "=========================================="
echo "Generate Values Files from Terraform"
echo "=========================================="
echo ""

cd "$TERRAFORM_DIR"

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
  echo "✗ ERROR: terraform.tfstate not found"
  echo "  Please run 'terraform apply' first"
  exit 1
fi

# Extract values from Terraform
echo "Extracting configuration from Terraform..."

USER_PREFIX=$(terraform output -raw user_prefix 2>/dev/null || echo "ba")
REGION1=$(terraform output -raw region1 2>/dev/null || echo "us-east-1")
REGION2=$(terraform output -raw region2 2>/dev/null || echo "us-west-2")
HOSTED_ZONE_ID=$(grep "^dns_hosted_zone_id" terraform.tfvars | cut -d'"' -f2)

# Construct names based on Terraform naming convention
REC_NAME_R1="${USER_PREFIX}-rec-${REGION1}"
REC_NAME_R2="${USER_PREFIX}-rec-${REGION2}"

# Get EKS cluster names from Terraform outputs
EKS_CLUSTER_R1=$(terraform output -json region1_info 2>/dev/null | jq -r '.eks_cluster_name' || echo "${USER_PREFIX}-r1-${REC_NAME_R1}")
EKS_CLUSTER_R2=$(terraform output -json region2_info 2>/dev/null | jq -r '.eks_cluster_name' || echo "${USER_PREFIX}-r2-${REC_NAME_R2}")

# Get DNS configuration from tfvars
API_FQDN_R1=$(grep "region1_redis_api_fqdn_url" terraform.tfvars | cut -d'"' -f2)
DB_FQDN_R1=$(grep "region1_redis_db_fqdn_suffix" terraform.tfvars | cut -d'"' -f2)
API_FQDN_R2=$(grep "region2_redis_api_fqdn_url" terraform.tfvars | cut -d'"' -f2)
DB_FQDN_R2=$(grep "region2_redis_db_fqdn_suffix" terraform.tfvars | cut -d'"' -f2)

# Get credentials from tfvars
REDIS_PASSWORD=$(grep "redis_cluster_password" terraform.tfvars | cut -d'"' -f2)
REDIS_USERNAME=$(grep "redis_cluster_username" terraform.tfvars | cut -d'"' -f2)

# Get deployment automation configuration from tfvars
NAMESPACE=$(grep "^redis_namespace" terraform.tfvars | cut -d'"' -f2)
K8S_CONTEXT_R1=$(grep "^region1_kubectl_context" terraform.tfvars | cut -d'"' -f2)
K8S_CONTEXT_R2=$(grep "^region2_kubectl_context" terraform.tfvars | cut -d'"' -f2)
DNS_TTL=$(grep "^dns_ttl" terraform.tfvars | awk '{print $3}' | tr -d ' ')

# Get RERC configuration from tfvars
RERC_LOCAL_NAME_R1=$(grep "^region1_rerc_local_name" terraform.tfvars | cut -d'"' -f2)
RERC_REMOTE_NAME_R1=$(grep "^region1_rerc_remote_name" terraform.tfvars | cut -d'"' -f2)
RERC_LOCAL_SECRET_R1=$(grep "^region1_rerc_local_secret" terraform.tfvars | cut -d'"' -f2)
RERC_REMOTE_SECRET_R1=$(grep "^region1_rerc_remote_secret" terraform.tfvars | cut -d'"' -f2)

RERC_LOCAL_NAME_R2=$(grep "^region2_rerc_local_name" terraform.tfvars | cut -d'"' -f2)
RERC_REMOTE_NAME_R2=$(grep "^region2_rerc_remote_name" terraform.tfvars | cut -d'"' -f2)
RERC_LOCAL_SECRET_R2=$(grep "^region2_rerc_local_secret" terraform.tfvars | cut -d'"' -f2)
RERC_REMOTE_SECRET_R2=$(grep "^region2_rerc_remote_secret" terraform.tfvars | cut -d'"' -f2)

# Get REAADB configuration from tfvars
REAADB_NAME=$(grep "^reaadb_name" terraform.tfvars | cut -d'"' -f2)
REAADB_PORT=$(grep "^reaadb_port" terraform.tfvars | awk '{print $3}' | tr -d ' ')
REAADB_DATABASE_PORT=$(grep "^reaadb_database_port" terraform.tfvars | awk '{print $3}' | tr -d ' ')
REAADB_MEMORY_SIZE=$(grep "^reaadb_memory_size" terraform.tfvars | cut -d'"' -f2)
REAADB_SHARD_COUNT=$(grep "^reaadb_shard_count" terraform.tfvars | awk '{print $3}' | tr -d ' ')
REAADB_REPLICATION=$(grep "^reaadb_replication" terraform.tfvars | awk '{print $3}' | tr -d ' ')
REAADB_EVICTION_POLICY=$(grep "^reaadb_eviction_policy" terraform.tfvars | cut -d'"' -f2)
REAADB_SECRET_NAME=$(grep "^reaadb_secret_name" terraform.tfvars | cut -d'"' -f2)

# Get ingress configuration from tfvars
INGRESS_ENABLED=$(grep "^ingress_enabled" terraform.tfvars | awk '{print $3}' | tr -d ' ')
INGRESS_CLASSNAME=$(grep "^ingress_classname" terraform.tfvars | cut -d'"' -f2)

# Get REC node count from tfvars
REDIS_NODES=$(grep "^redis_nodes" terraform.tfvars | awk '{print $3}' | tr -d ' ')

echo "Configuration:"
echo "  User Prefix: $USER_PREFIX"
echo "  Region 1: $REGION1"
echo "  Region 2: $REGION2"
echo "  REC Name R1: $REC_NAME_R1"
echo "  REC Name R2: $REC_NAME_R2"
echo "  EKS Cluster R1: $EKS_CLUSTER_R1"
echo "  EKS Cluster R2: $EKS_CLUSTER_R2"
echo "  Namespace: $NAMESPACE"
echo "  Kubectl Context R1: $K8S_CONTEXT_R1"
echo "  Kubectl Context R2: $K8S_CONTEXT_R2"
echo "  Hosted Zone ID: $HOSTED_ZONE_ID"
echo "  DNS TTL: $DNS_TTL"
echo "  REAADB Name: $REAADB_NAME"
echo "  REAADB Port: $REAADB_PORT"
echo "  Ingress Class: $INGRESS_CLASSNAME"
echo ""

# Generate values-region1.yaml
echo "Generating values-region1.yaml..."
cat > "$DEPLOY_DIR/values-region1.yaml" <<EOF
# Redis Enterprise Active-Active Deployment - Region 1
# Auto-generated from Terraform configuration
# Generated: $(date)

cluster:
  name: region1
  region: $REGION1
  k8s_context: $K8S_CONTEXT_R1
  eksClusterName: $EKS_CLUSTER_R1

rec:
  name: $REC_NAME_R1
  namespace: $NAMESPACE
  nodes: $REDIS_NODES

ingress:
  enabled: $INGRESS_ENABLED
  className: $INGRESS_CLASSNAME
  apiFqdn: $API_FQDN_R1
  dbFqdnSuffix: $DB_FQDN_R1

rerc:
  local:
    name: $RERC_LOCAL_NAME_R1
    recName: $REC_NAME_R1
    apiFqdnUrl: $API_FQDN_R1
    dbFqdnSuffix: $DB_FQDN_R1
    secretName: $RERC_LOCAL_SECRET_R1
  remote:
    name: $RERC_REMOTE_NAME_R1
    recName: $REC_NAME_R2
    apiFqdnUrl: $API_FQDN_R2
    dbFqdnSuffix: $DB_FQDN_R2
    secretName: $RERC_REMOTE_SECRET_R1

credentials:
  username: $REDIS_USERNAME
  password: $REDIS_PASSWORD

reaadb:
  enabled: false
  name: $REAADB_NAME
  port: $REAADB_PORT
  password: $REDIS_PASSWORD
  participatingClusters:
    - $RERC_LOCAL_NAME_R1
    - $RERC_REMOTE_NAME_R1
  databasePort: $REAADB_DATABASE_PORT
  memorySize: $REAADB_MEMORY_SIZE
  shardCount: $REAADB_SHARD_COUNT
  replication: $REAADB_REPLICATION
  evictionPolicy: $REAADB_EVICTION_POLICY
  secretName: $REAADB_SECRET_NAME

dns:
  hostedZoneId: $HOSTED_ZONE_ID
  ttl: $DNS_TTL
EOF

echo "✓ Generated: $DEPLOY_DIR/values-region1.yaml"

# Generate values-region2.yaml
echo "Generating values-region2.yaml..."
cat > "$DEPLOY_DIR/values-region2.yaml" <<EOF
# Redis Enterprise Active-Active Deployment - Region 2
# Auto-generated from Terraform configuration
# Generated: $(date)

cluster:
  name: region2
  region: $REGION2
  k8s_context: $K8S_CONTEXT_R2
  eksClusterName: $EKS_CLUSTER_R2

rec:
  name: $REC_NAME_R2
  namespace: $NAMESPACE
  nodes: $REDIS_NODES

ingress:
  enabled: $INGRESS_ENABLED
  className: $INGRESS_CLASSNAME
  apiFqdn: $API_FQDN_R2
  dbFqdnSuffix: $DB_FQDN_R2

rerc:
  local:
    name: $RERC_LOCAL_NAME_R2
    recName: $REC_NAME_R2
    apiFqdnUrl: $API_FQDN_R2
    dbFqdnSuffix: $DB_FQDN_R2
    secretName: $RERC_LOCAL_SECRET_R2
  remote:
    name: $RERC_REMOTE_NAME_R2
    recName: $REC_NAME_R1
    apiFqdnUrl: $API_FQDN_R1
    dbFqdnSuffix: $DB_FQDN_R1
    secretName: $RERC_REMOTE_SECRET_R2

credentials:
  username: $REDIS_USERNAME
  password: $REDIS_PASSWORD

reaadb:
  enabled: false
  name: $REAADB_NAME
  port: $REAADB_PORT
  password: $REDIS_PASSWORD
  participatingClusters:
    - $RERC_LOCAL_NAME_R2
    - $RERC_REMOTE_NAME_R2
  databasePort: $REAADB_DATABASE_PORT
  memorySize: $REAADB_MEMORY_SIZE
  shardCount: $REAADB_SHARD_COUNT
  replication: $REAADB_REPLICATION
  evictionPolicy: $REAADB_EVICTION_POLICY
  secretName: $REAADB_SECRET_NAME

dns:
  hostedZoneId: $HOSTED_ZONE_ID
  ttl: $DNS_TTL
EOF

echo "✓ Generated: $DEPLOY_DIR/values-region2.yaml"
echo ""
echo "=========================================="
echo "✓ Values Files Generated Successfully"
echo "=========================================="
echo ""

