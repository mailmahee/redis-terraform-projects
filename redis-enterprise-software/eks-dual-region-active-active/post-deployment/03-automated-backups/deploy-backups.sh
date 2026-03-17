#!/bin/bash

#==============================================================================
# AUTOMATED BACKUPS DEPLOYMENT SCRIPT
#==============================================================================
# This script configures automated backups for Redis databases
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
echo "  Automated Backups Deployment"
echo "=========================================================================="
echo ""

# Load configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ ERROR: config.env not found${NC}"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${BLUE}📋 Configuration loaded${NC}"
echo "  S3 Bucket: $S3_BACKUP_BUCKET"
echo "  Backup Interval: $BACKUP_INTERVAL"
echo "  Namespace: $NAMESPACE"
echo ""

# Create S3 bucket if it doesn't exist
echo -e "${BLUE}🪣 Checking S3 bucket...${NC}"
if ! aws s3 ls "s3://$S3_BACKUP_BUCKET" --profile ${AWS_PROFILE:-default} 2>/dev/null; then
    echo -e "${YELLOW}Creating S3 bucket: $S3_BACKUP_BUCKET${NC}"
    aws s3 mb "s3://$S3_BACKUP_BUCKET" --region $AWS_REGION1 --profile ${AWS_PROFILE:-default}
    
    # Apply lifecycle policy
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BACKUP_BUCKET" \
        --lifecycle-configuration file://s3-lifecycle-policy.json \
        --profile ${AWS_PROFILE:-default}
else
    echo -e "${GREEN}✅ S3 bucket exists${NC}"
fi

echo ""
echo "=========================================================================="
echo -e "${GREEN}✅ Automated Backups Configured!${NC}"
echo "=========================================================================="
echo ""
echo "S3 Bucket: $S3_BACKUP_BUCKET"
echo ""
echo "To configure backup for a database, apply the backup configuration:"
echo "  kubectl apply -f database-backup-patch.yaml --context $REGION1_CONTEXT"
echo ""

