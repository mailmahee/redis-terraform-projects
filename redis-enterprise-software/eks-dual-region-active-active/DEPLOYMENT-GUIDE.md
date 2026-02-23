# Redis Enterprise Active-Active Deployment Guide

This guide covers the fully automated deployment of Redis Enterprise Active-Active (CRDB) across dual AWS regions using EKS and Terraform.

## Overview

This deployment is **100% automated** with zero manual intervention required. All configuration is dynamically extracted from `terraform.tfvars`, and the deployment orchestration handles all steps from infrastructure provisioning to bidirectional replication testing.

## Quick Start

```bash
# 1. Configure your deployment
cd redis-enterprise-software/eks-dual-region-active-active
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS account ID and configuration

# 2. Deploy infrastructure
terraform init
terraform apply -auto-approve

# 3. Run automated deployment
cd deploy
bash scripts/generate-values.sh
bash scripts/deploy-all.sh
```

That's it! The deployment will run from start to finish automatically.

## Architecture

The deployment creates:
- **Two Redis Enterprise Clusters** (one per region: us-east-1, us-west-2)
- **VPC Peering** for cross-region connectivity
- **NGINX Ingress** for external access
- **Route53 DNS** for API and database endpoints
- **Active-Active Database (CRDB)** with bidirectional replication

## Deployment Steps (Automated)

The `deploy-all.sh` script executes these steps automatically:

1. ✅ Verify Terraform Infrastructure
2. ✅ Configure kubectl Contexts
3. ✅ Validate Redis Enterprise Clusters
4. ✅ Setup Admission Controllers
5. ✅ Validate Ingress Resources
6. ✅ Validate API DNS Records
7. ✅ Deploy Remote Cluster References (RERCs)
8. ✅ Validate RERCs (local/remote status)
9. ✅ Deploy Active-Active Database (REAADB)
10. ✅ Create Database DNS Records
11. ✅ Validate REAADB (CRDB status, peer sync)
12. ✅ Test Bidirectional Replication

## Key Features

### 100% Dynamic Configuration
- All values extracted from `terraform.tfvars`
- Zero hardcoded values in deployment scripts
- Automatic service discovery for database endpoints
- Auto-generated REC names, DNS FQDNs, and secrets

### Comprehensive Validation
- Each step validated before proceeding
- Clear success/failure indicators (✓/✗)
- Detailed error messages with troubleshooting hints
- Exit codes for CI/CD integration

### Automatic DNS Management
- API DNS records created by Terraform
- Database DNS records created automatically after REAADB deployment
- Supports both CNAME and A records
- Handles record updates (UPSERT)

## Configuration

All configuration is in `terraform.tfvars`. Key sections:

### Infrastructure
- `user_prefix` - Prefix for all resources (e.g., "ba")
- `region1`, `region2` - AWS regions
- `aws_account_id` - Your AWS account ID

### Redis Enterprise
- `redis_namespace` - Kubernetes namespace (default: "redis-enterprise")
- `redis_cluster_nodes` - Number of REC nodes per cluster (default: 3)
- `redis_enable_ingress` - Enable ingress (default: true)

### Active-Active Database
- `reaadb_name` - Database name
- `reaadb_memory_size` - Memory per shard (e.g., "100mb")
- `reaadb_shard_count` - Number of shards
- `reaadb_replication` - Replication enabled
- `reaadb_eviction_policy` - Eviction policy (e.g., "volatile-lru")

### DNS
- `dns_hosted_zone_id` - Route53 hosted zone ID
- `dns_domain` - Domain name (e.g., "redisdemo.com")

See `terraform.tfvars.example` for complete configuration options.

## Validation Scripts

Individual validation scripts can be run manually:

```bash
cd deploy

# Validate REC deployment
bash scripts/validate-rec.sh values-region1.yaml

# Validate ingress resources
bash scripts/validate-ingress.sh values-region1.yaml

# Validate DNS resolution
bash scripts/validate-dns.sh values-region1.yaml

# Validate RERC status
bash scripts/validate-rerc.sh values-region1.yaml values-region2.yaml

# Validate REAADB deployment
bash scripts/validate-reaadb.sh values-region1.yaml

# Test bidirectional replication
bash scripts/validate-replication.sh values-region1.yaml values-region2.yaml
```

## Troubleshooting

### Check Operator Logs
```bash
kubectl logs -n redis-enterprise -l name=redis-enterprise-operator --context=region1-new
```

### Check REC Status
```bash
kubectl get rec -n redis-enterprise --context=region1-new
kubectl describe rec <rec-name> -n redis-enterprise --context=region1-new
```

### Check REAADB Status
```bash
kubectl get reaadb -n redis-enterprise --context=region1-new
kubectl describe reaadb <reaadb-name> -n redis-enterprise --context=region1-new
```

### Use Troubleshooting Scripts
```bash
bash scripts/troubleshoot-crdb.sh values-region1.yaml
bash scripts/troubleshoot-reaadb-pending.sh values-region1.yaml
```

## Cleanup

To destroy all resources:

```bash
cd redis-enterprise-software/eks-dual-region-active-active
terraform destroy -auto-approve
```

The destroy process automatically:
1. Deletes DNS records
2. Deletes custom resources (REAADB, RERC, REDB, REC)
3. Deletes Kubernetes resources
4. Deletes EKS clusters
5. Deletes VPCs and networking

## Documentation

- `README.md` - Project overview and architecture
- `DEPLOYMENT-GUIDE.md` - This file
- `DYNAMIC-CONFIGURATION.md` - Dynamic configuration details
- `DELETE_RESOURCES.md` - Resource deletion order
- `deploy/README-AUTOMATED-DEPLOYMENT.md` - Detailed deployment steps
- `deploy/CRDB-TROUBLESHOOTING.md` - CRDB troubleshooting guide
- `deploy/REAADB-PENDING-TROUBLESHOOTING.md` - REAADB pending state troubleshooting

