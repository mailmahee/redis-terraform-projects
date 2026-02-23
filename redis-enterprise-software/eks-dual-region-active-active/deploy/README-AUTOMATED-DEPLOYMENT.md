# Redis Enterprise Active-Active - Automated Deployment

This guide provides a fully automated deployment process for Redis Enterprise Active-Active (CRDB) across dual AWS regions using EKS and Terraform.

## Overview

The automated deployment system provides:
- **100% Automated** - Zero manual intervention required
- **Dynamic Configuration** - All values extracted from `terraform.tfvars`
- **Comprehensive Validation** - Each step validated before proceeding
- **DNS Automation** - Automatic DNS record creation and management
- **Bidirectional Replication Testing** - Automated verification of Active-Active functionality

**Key Feature**: All configuration is extracted from `terraform.tfvars` - no hardcoded values anywhere! See [DYNAMIC-CONFIGURATION.md](../DYNAMIC-CONFIGURATION.md) for details.

## Prerequisites

1. **Terraform deployed**:
   ```bash
   cd redis-enterprise-software/eks-dual-region-active-active
   terraform apply
   ```

2. **Required tools installed**:
   - `kubectl`
   - `aws` CLI (configured with credentials)
   - `yq` (YAML processor)
   - `jq` (JSON processor)
   - `dig` (DNS lookup)

3. **AWS Route53 Hosted Zone** configured in `terraform.tfvars`:
   ```hcl
   dns_hosted_zone_id = "ZIDQVXMJG58IE"
   ```

## Quick Start - Automated Deployment

### Step 1: Generate Configuration Files

Generate values files from your Terraform configuration:

```bash
cd redis-enterprise-software/eks-dual-region-active-active/deploy
bash scripts/generate-values.sh
```

This creates:
- `values-region1.yaml` - Configuration for Region 1
- `values-region2.yaml` - Configuration for Region 2

### Step 2: Run Complete Deployment

Execute the master orchestration script:

```bash
bash scripts/deploy-all.sh
```

This script will:
1. ✅ Verify Terraform infrastructure is deployed
2. ✅ Configure kubectl contexts for both regions
3. ✅ Wait for and validate RECs (Redis Enterprise Clusters)
4. ✅ Setup admission controllers
5. ✅ Validate ingress resources
6. ✅ Validate DNS records for API endpoints
7. ✅ Deploy RERCs (Remote Cluster references)
8. ✅ Validate RERCs (local/remote status)
9. ✅ Deploy REAADB (Active-Active Database)
10. ✅ Validate REAADB deployment
11. ✅ Create DNS records for database endpoints
12. ✅ Validate database DNS records
13. ✅ Test bidirectional replication

**Total time**: ~15-20 minutes (most time is waiting for resources to become ready)

## Manual Step-by-Step Deployment

If you prefer to run steps individually for troubleshooting:

### 1. Validate RECs

```bash
bash scripts/validate-rec.sh values-region1.yaml
bash scripts/validate-rec.sh values-region2.yaml
```

### 2. Setup Admission Controllers

```bash
bash scripts/setup-admission.sh values-region1.yaml
bash scripts/setup-admission.sh values-region2.yaml
```

### 3. Validate Ingress

```bash
bash scripts/validate-ingress.sh values-region1.yaml
bash scripts/validate-ingress.sh values-region2.yaml
```

### 4. Validate DNS

```bash
bash scripts/validate-dns.sh values-region1.yaml
bash scripts/validate-dns.sh values-region2.yaml
```

### 5. Deploy RERCs

```bash
bash scripts/deploy-rerc.sh values-region1.yaml
bash scripts/deploy-rerc.sh values-region2.yaml
```

### 6. Validate RERCs

```bash
bash scripts/validate-rerc.sh values-region1.yaml
bash scripts/validate-rerc.sh values-region2.yaml
```

### 7. Deploy REAADB

```bash
bash scripts/deploy-reaadb.sh values-region1.yaml
```

### 8. Validate REAADB

```bash
bash scripts/validate-reaadb.sh values-region1.yaml
bash scripts/validate-reaadb.sh values-region2.yaml
```

### 9. Create Database DNS Records

```bash
bash scripts/create-dns-records.sh values-region1.yaml ZIDQVXMJG58IE
bash scripts/create-dns-records.sh values-region2.yaml ZIDQVXMJG58IE
```

### 10. Test Replication

```bash
bash scripts/validate-replication.sh values-region1.yaml values-region2.yaml
```

## Validation Scripts

Each validation script checks specific aspects of the deployment:

| Script | Purpose |
|--------|---------|
| `validate-rec.sh` | Validates REC status, ingressOrRouteSpec configuration, pods |
| `validate-ingress.sh` | Validates NGINX controller, ingress resources, load balancers |
| `validate-dns.sh` | Validates DNS resolution (external and internal) |
| `validate-rerc.sh` | Validates RERC status and local/remote detection |
| `validate-reaadb.sh` | Validates REAADB status, CRDB details, connectivity |
| `validate-replication.sh` | Tests bidirectional data replication |

## Configuration Files

### values-region1.yaml / values-region2.yaml

These files contain all configuration for each region:

```yaml
cluster:
  name: region1
  region: us-east-1
  k8s_context: region1-new
  eksClusterName: ba-r1-eks-us-east-1

rec:
  name: ba-rec-us-east-1  # Must match Terraform
  namespace: redis-enterprise
  nodes: 3

ingress:
  enabled: true
  className: nginx
  apiFqdn: api-rec-region1-redis-enterprise.redisdemo.com
  dbFqdnSuffix: -db-rec-region1-redis-enterprise.redisdemo.com

rerc:
  local:
    name: rerc-region1
    recName: ba-rec-us-east-1
    # ... more config

dns:
  hostedZoneId: ZIDQVXMJG58IE
  ttl: 300
```

## Troubleshooting

### REC Not Running

```bash
kubectl describe rec <rec-name> -n redis-enterprise --context=<context>
kubectl logs -n redis-enterprise -l name=redis-enterprise-operator
```

### Ingress Not Getting Load Balancer

```bash
kubectl get ingress -n redis-enterprise --context=<context>
kubectl describe ingress <ingress-name> -n redis-enterprise --context=<context>
```

### DNS Not Resolving

```bash
dig @8.8.8.8 +short <fqdn>
aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
```

### RERC Shows Wrong local/remote Status

Check that `recName` in RERC matches the actual REC name:
```bash
kubectl get rerc <rerc-name> -n redis-enterprise --context=<context> -o yaml
```

### Replication Not Working

Check CRDB peer status:
```bash
bash scripts/troubleshoot-crdb.sh values-region1.yaml
```

## What Was Fixed

This automated deployment fixes several critical issues:

1. **Missing ingress annotations**: Added `kubernetes.io/ingress.class: nginx` to Terraform defaults
2. **Wildcard DNS not working**: Automated creation of specific DNS records for each database
3. **Manual intervention required**: All steps now automated with validation
4. **Configuration mismatches**: Values files generated from Terraform to ensure consistency

## Next Steps

After successful deployment:

1. **Access the database** from either region
2. **Monitor replication** status
3. **Create additional databases** as needed
4. **Configure applications** to use the Active-Active database

## Cleanup

To remove all resources:

```bash
bash scripts/cleanup-reaadb.sh values-region1.yaml
bash scripts/cleanup-reaadb.sh values-region2.yaml
cd .. && terraform destroy
```

