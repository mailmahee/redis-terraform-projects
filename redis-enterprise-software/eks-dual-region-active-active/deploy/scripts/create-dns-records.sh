#!/bin/bash
# Create DNS records for database endpoints
# Usage: ./create-dns-records.sh <values-file> <hosted-zone-id>

set -e

VALUES_FILE=$1
HOSTED_ZONE_ID=$2

if [ -z "$VALUES_FILE" ] || [ -z "$HOSTED_ZONE_ID" ]; then
  echo "Usage: $0 <values-file> <hosted-zone-id>"
  echo ""
  echo "Example:"
  echo "  $0 values-region1.yaml ZIDQVXMJG58IE"
  exit 1
fi

if [ ! -f "$VALUES_FILE" ]; then
  echo "ERROR: Values file not found: $VALUES_FILE"
  exit 1
fi

# Load configuration
if ! command -v yq &> /dev/null; then
  echo "ERROR: yq is required but not installed."
  exit 1
fi

K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REC_NAME=$(yq eval '.rec.name' "$VALUES_FILE")
CLUSTER_NAME=$(yq eval '.cluster.name' "$VALUES_FILE")
DB_FQDN_SUFFIX=$(yq eval '.ingress.dbFqdnSuffix' "$VALUES_FILE")
DNS_TTL=$(yq eval '.dns.ttl // 300' "$VALUES_FILE")

echo "=========================================="
echo "DNS Record Creation"
echo "=========================================="
echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "Hosted Zone: $HOSTED_ZONE_ID"
echo ""

# Get LoadBalancer address
echo "=== Step 1: Getting LoadBalancer Address ==="
LB_HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx --context="$K8S_CONTEXT" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

if [ -z "$LB_HOSTNAME" ] && [ -z "$LB_IP" ]; then
  echo "✗ ERROR: Cannot determine LoadBalancer address"
  exit 1
fi

if [ -n "$LB_HOSTNAME" ]; then
  LB_ADDRESS="$LB_HOSTNAME"
  RECORD_TYPE="CNAME"
  echo "✓ LoadBalancer hostname: $LB_HOSTNAME"
elif [ -n "$LB_IP" ]; then
  LB_ADDRESS="$LB_IP"
  RECORD_TYPE="A"
  echo "✓ LoadBalancer IP: $LB_IP"
fi
echo ""

# Get list of databases
echo "=== Step 2: Finding Databases ==="
DB_LIST=$(kubectl get redb -n "$NAMESPACE" --context="$K8S_CONTEXT" --no-headers 2>/dev/null | awk '{print $1}' || echo "")

if [ -z "$DB_LIST" ]; then
  echo "ℹ No databases found - nothing to do"
  exit 0
fi

echo "Found databases:"
for DB_NAME in $DB_LIST; do
  echo "  - $DB_NAME"
done
echo ""

# Create DNS records for each database
echo "=== Step 3: Creating DNS Records ==="
for DB_NAME in $DB_LIST; do
  DB_FQDN="${DB_NAME}${DB_FQDN_SUFFIX}"
  echo ""
  echo "Creating DNS record for: $DB_FQDN"
  echo "  Type: $RECORD_TYPE"
  echo "  Target: $LB_ADDRESS"
  echo "  TTL: $DNS_TTL"
  
  # Check if record already exists
  EXISTING=$(aws route53 list-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --query "ResourceRecordSets[?Name=='${DB_FQDN}.']" \
    --output json 2>/dev/null || echo "[]")
  
  if [ "$EXISTING" != "[]" ] && [ "$EXISTING" != "" ]; then
    echo "  ℹ Record already exists, updating..."
    ACTION="UPSERT"
  else
    echo "  Creating new record..."
    ACTION="CREATE"
  fi
  
  # Create change batch JSON
  if [ "$RECORD_TYPE" == "CNAME" ]; then
    CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "$ACTION",
    "ResourceRecordSet": {
      "Name": "$DB_FQDN",
      "Type": "CNAME",
      "TTL": $DNS_TTL,
      "ResourceRecords": [{"Value": "$LB_ADDRESS"}]
    }
  }]
}
EOF
)
  else
    CHANGE_BATCH=$(cat <<EOF
{
  "Changes": [{
    "Action": "$ACTION",
    "ResourceRecordSet": {
      "Name": "$DB_FQDN",
      "Type": "A",
      "TTL": $DNS_TTL,
      "ResourceRecords": [{"Value": "$LB_ADDRESS"}]
    }
  }]
}
EOF
)
  fi
  
  # Apply DNS change
  CHANGE_ID=$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$HOSTED_ZONE_ID" \
    --change-batch "$CHANGE_BATCH" \
    --query 'ChangeInfo.Id' \
    --output text 2>/dev/null || echo "ERROR")
  
  if [ "$CHANGE_ID" == "ERROR" ]; then
    echo "  ✗ ERROR: Failed to create DNS record"
    exit 1
  fi
  
  echo "  ✓ DNS record created/updated (Change ID: $CHANGE_ID)"
done

echo ""
echo "=========================================="
echo "✓ DNS Records Created Successfully"
echo "=========================================="
echo ""
echo "DNS records may take a few minutes to propagate."
echo "Test with: dig @8.8.8.8 +short <database-fqdn>"
echo ""

