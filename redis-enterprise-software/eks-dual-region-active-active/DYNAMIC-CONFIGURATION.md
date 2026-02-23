# Dynamic Configuration Guide

This document explains how the deployment automation system extracts all configuration from `terraform.tfvars` to ensure **zero hardcoded values**.

## Overview

All deployment configuration is now **100% dynamic** and extracted from `terraform.tfvars`. The `generate-values.sh` script reads Terraform configuration and generates deployment values files with no hardcoded values.

## Configuration Sources

### ✅ Fully Dynamic (Extracted from terraform.tfvars)

| Configuration | tfvars Variable | Used In |
|---------------|-----------------|---------|
| **Hosted Zone ID** | `dns_hosted_zone_id` | DNS record creation |
| **DNS TTL** | `dns_ttl` | DNS record TTL |
| **Regions** | `region1`, `region2` | All region-specific config |
| **User Prefix** | `user_prefix` | Resource naming |
| **Namespace** | `redis_namespace` | Kubernetes namespace |
| **Kubectl Contexts** | `region1_kubectl_context`, `region2_kubectl_context` | kubectl commands |
| **REC Nodes** | `redis_nodes` | REC node count |
| **Credentials** | `redis_cluster_username`, `redis_cluster_password` | Authentication |
| **API FQDNs** | `region1_redis_api_fqdn_url`, `region2_redis_api_fqdn_url` | API endpoints |
| **DB FQDN Suffixes** | `region1_redis_db_fqdn_suffix`, `region2_redis_db_fqdn_suffix` | Database endpoints |
| **RERC Names** | `region1_rerc_local_name`, `region1_rerc_remote_name`, etc. | RERC resources |
| **RERC Secrets** | `region1_rerc_local_secret`, `region1_rerc_remote_secret`, etc. | RERC authentication |
| **REAADB Name** | `reaadb_name` | Database name |
| **REAADB Port** | `reaadb_port` | REC API port |
| **Database Port** | `reaadb_database_port` | Actual database port |
| **Memory Size** | `reaadb_memory_size` | Database memory |
| **Shard Count** | `reaadb_shard_count` | Database shards |
| **Replication** | `reaadb_replication` | Database replication |
| **Eviction Policy** | `reaadb_eviction_policy` | Database eviction |
| **Secret Name** | `reaadb_secret_name` | Database secret |
| **Ingress Enabled** | `ingress_enabled` | Ingress configuration |
| **Ingress Class** | `ingress_classname` | Ingress class name |

### 🔧 Auto-Constructed (Derived from tfvars)

| Configuration | Pattern | Example |
|---------------|---------|---------|
| **REC Names** | `${user_prefix}-rec-${region}` | `ba-rec-us-east-1` |
| **EKS Cluster Names** | `${user_prefix}-r1-eks-${region}` | `ba-r1-eks-us-east-1` |

## terraform.tfvars Configuration

### Required Variables

```hcl
# Basic Configuration
user_prefix = "ba"
region1 = "us-east-1"
region2 = "us-west-2"

# Credentials
redis_cluster_username = "admin@redis.com"
redis_cluster_password = "RedisTest123"

# DNS Configuration
region1_redis_api_fqdn_url   = "api-rec-region1-redis-enterprise.redisdemo.com"
region1_redis_db_fqdn_suffix = "-db-rec-region1-redis-enterprise.redisdemo.com"
region2_redis_api_fqdn_url   = "api-rec-region2-redis-enterprise.redisdemo.com"
region2_redis_db_fqdn_suffix = "-db-rec-region2-redis-enterprise.redisdemo.com"

dns_hosted_zone_id = "ZIDQVXMJG58IE"
dns_ttl = 300
```

### Deployment Automation Variables

```hcl
# Kubernetes Configuration
redis_namespace = "redis-enterprise"
redis_nodes = 3

# Kubectl Context Names
region1_kubectl_context = "region1-new"
region2_kubectl_context = "region2-new"

# RERC Configuration
region1_rerc_local_name  = "rerc-region1"
region1_rerc_remote_name = "rerc-region2"
region2_rerc_local_name  = "rerc-region2"
region2_rerc_remote_name = "rerc-region1"

region1_rerc_local_secret  = "redis-enterprise-rerc-region1"
region1_rerc_remote_secret = "redis-enterprise-rerc-region2"
region2_rerc_local_secret  = "redis-enterprise-rerc-region2"
region2_rerc_remote_secret = "redis-enterprise-rerc-region1"

# REAADB Configuration
reaadb_name           = "aadb-sample"
reaadb_port           = 19769
reaadb_database_port  = 12000
reaadb_memory_size    = "100MB"
reaadb_shard_count    = 1
reaadb_replication    = true
reaadb_eviction_policy = "volatile-lru"
reaadb_secret_name    = "aadb-sample-secret"

# Ingress Configuration
ingress_enabled   = true
ingress_classname = "nginx"
```

## How It Works

### 1. Generate Values Files

```bash
cd redis-enterprise-software/eks-dual-region-active-active/deploy
bash scripts/generate-values.sh
```

This script:
1. Reads `terraform.tfvars` from parent directory
2. Extracts all configuration values
3. Constructs derived values (REC names, EKS cluster names)
4. Generates `values-region1.yaml` and `values-region2.yaml`

### 2. Values Files Structure

Generated files contain all configuration needed for deployment:

```yaml
cluster:
  name: region1                    # Logical name
  region: us-east-1                # From tfvars
  k8s_context: region1-new         # From tfvars
  eksClusterName: ba-r1-eks-us-east-1  # Constructed

rec:
  name: ba-rec-us-east-1           # Constructed
  namespace: redis-enterprise      # From tfvars
  nodes: 3                         # From tfvars

rerc:
  local:
    name: rerc-region1             # From tfvars
    secretName: redis-enterprise-rerc-region1  # From tfvars
  remote:
    name: rerc-region2             # From tfvars
    secretName: redis-enterprise-rerc-region2  # From tfvars

reaadb:
  name: aadb-sample                # From tfvars
  port: 19769                      # From tfvars
  databasePort: 12000              # From tfvars
  memorySize: 100MB                # From tfvars
  # ... all from tfvars

dns:
  hostedZoneId: ZIDQVXMJG58IE      # From tfvars
  ttl: 300                         # From tfvars
```

## Customization Examples

### Change Database Configuration

Edit `terraform.tfvars`:
```hcl
reaadb_name = "production-db"
reaadb_memory_size = "10GB"
reaadb_shard_count = 3
```

Regenerate values:
```bash
bash scripts/generate-values.sh
```

### Change Kubectl Context Names

Edit `terraform.tfvars`:
```hcl
region1_kubectl_context = "prod-us-east-1"
region2_kubectl_context = "prod-us-west-2"
```

Regenerate and reconfigure:
```bash
bash scripts/generate-values.sh
# Contexts will be updated in values files
```

### Change Namespace

Edit `terraform.tfvars`:
```hcl
redis_namespace = "redis-production"
```

**Note**: This requires Terraform redeployment as namespace is used during infrastructure creation.

## Benefits

✅ **Single Source of Truth**: All configuration in `terraform.tfvars`  
✅ **No Hardcoded Values**: Everything extracted dynamically  
✅ **Easy Customization**: Change tfvars and regenerate  
✅ **Consistency**: Values files always match Terraform  
✅ **Version Control**: Track all changes in tfvars  

## Validation

After generating values files, verify configuration:

```bash
# Check generated values
cat deploy/values-region1.yaml
cat deploy/values-region2.yaml

# Verify all values match tfvars
grep "reaadb_name" terraform.tfvars
grep "name:" deploy/values-region1.yaml | grep reaadb -A 1
```

## Troubleshooting

### Values Not Updating

**Problem**: Generated values don't reflect tfvars changes

**Solution**:
```bash
# Ensure you're in the right directory
cd redis-enterprise-software/eks-dual-region-active-active

# Regenerate values
bash deploy/scripts/generate-values.sh

# Verify tfvars syntax
terraform validate
```

### Missing Values

**Problem**: Some values are empty in generated files

**Solution**: Check that all required variables are set in `terraform.tfvars`. See the "Required Variables" section above.


