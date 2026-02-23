# Redis Enterprise on AWS EKS - Dual Region Active-Active

## Overview

This is a **production-ready, fully automated Active-Active deployment** that deploys Redis Enterprise across two AWS regions with VPC peering and Active-Active (CRDB) database configuration.

**Key Features:**
- ✅ **100% Automated** - Zero manual intervention required
- ✅ **Dual Region Deployment** - us-east-1 and us-west-2 (configurable)
- ✅ **VPC Peering** - Automatic cross-region connectivity
- ✅ **Active-Active (CRDB)** - Bidirectional replication with conflict resolution
- ✅ **Dynamic Configuration** - All values extracted from `terraform.tfvars`
- ✅ **Comprehensive Validation** - Automated testing at each deployment phase
- ✅ **DNS Automation** - Automatic Route53 DNS record management

## Architecture

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│  Region 1 (us-east-1)           │    │  Region 2 (us-west-2)           │
│                                 │    │                                 │
│  ┌───────────────────────────┐  │    │  ┌───────────────────────────┐  │
│  │  VPC (10.1.0.0/16)        │  │    │  │  VPC (10.2.0.0/16)        │  │
│  │                           │  │    │  │                           │  │
│  │  ┌─────────────────────┐  │  │    │  │  ┌─────────────────────┐  │  │
│  │  │  EKS Cluster        │  │  │    │  │  │  EKS Cluster        │  │  │
│  │  │  - 3 worker nodes   │  │  │    │  │  │  - 3 worker nodes   │  │  │
│  │  │  - Redis Operator   │  │  │    │  │  │  - Redis Operator   │  │  │
│  │  │  - Redis Ent (3)    │  │  │    │  │  │  - Redis Ent (3)    │  │  │
│  │  │  - Sample DB        │  │  │    │  │  │  - Sample DB        │  │  │
│  │  └─────────────────────┘  │  │    │  │  └─────────────────────┘  │  │
│  └───────────────────────────┘  │    │  └───────────────────────────┘  │
└─────────────────────────────────┘    └─────────────────────────────────┘
                │                                      │
                └──────────── VPC Peering ─────────────┘
```

## Quick Start

### 1. Configure

```bash
cd redis-enterprise-software/eks-dual-region-active-active
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS account ID and configuration
```

### 2. Deploy Infrastructure

```bash
terraform init
terraform apply -auto-approve
```

### 3. Run Automated Deployment

```bash
cd deploy
bash scripts/generate-values.sh
bash scripts/deploy-all.sh
```

That's it! The deployment will:
- Deploy both Redis Enterprise Clusters
- Configure VPC peering
- Setup NGINX ingress
- Create DNS records
- Deploy Active-Active database
- Test bidirectional replication

**Total deployment time:** ~25-30 minutes

## Documentation

📖 **Complete guides:**

- **[DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)** - Complete deployment guide
- **[DYNAMIC-CONFIGURATION.md](./DYNAMIC-CONFIGURATION.md)** - Dynamic configuration details
- **[deploy/README-AUTOMATED-DEPLOYMENT.md](./deploy/README-AUTOMATED-DEPLOYMENT.md)** - Detailed deployment steps
- **[DELETE_RESOURCES.md](./DELETE_RESOURCES.md)** - Resource deletion guide
- **[deploy/CRDB-TROUBLESHOOTING.md](./deploy/CRDB-TROUBLESHOOTING.md)** - CRDB troubleshooting
- **[deploy/REAADB-PENDING-TROUBLESHOOTING.md](./deploy/REAADB-PENDING-TROUBLESHOOTING.md)** - REAADB troubleshooting

## Configuration

All configuration is managed in `terraform.tfvars`. Key sections:

### Infrastructure Configuration
```hcl
user_prefix        = "ba"              # Prefix for all resources
aws_account_id     = "123456789012"    # Your AWS account ID
region1            = "us-east-1"       # Primary region
region2            = "us-west-2"       # Secondary region
```

### Redis Enterprise Configuration
```hcl
redis_namespace         = "redis-enterprise"
redis_cluster_nodes     = 3
redis_enable_ingress    = true
redis_operator_version  = "v7.4.6-2"
```

### Active-Active Database Configuration
```hcl
reaadb_name            = "aadb-sample"
reaadb_memory_size     = "100mb"
reaadb_shard_count     = 1
reaadb_replication     = true
reaadb_eviction_policy = "volatile-lru"
```

### DNS Configuration
```hcl
dns_hosted_zone_id = "ZIDQVXMJG58IE"
dns_domain         = "redisdemo.com"
```

See `terraform.tfvars.example` for complete configuration options.

## What Gets Deployed

**Per Region:**
- VPC with public and private subnets
- EKS Cluster with managed node group (3 nodes)
- Redis Enterprise Operator
- Redis Enterprise Cluster (REC) with 3 nodes
- NGINX Ingress Controller
- Route53 DNS records for API and database endpoints

**Cross-Region:**
- VPC Peering Connection
- Route table entries for cross-region traffic
- Remote Cluster References (RERCs)
- Active-Active Database (REAADB/CRDB)

**Total Resources:** ~128 Terraform resources

## Validation

The automated deployment includes comprehensive validation:

```bash
# Validate REC deployment
cd deploy
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

### Check Deployment Status
```bash
# Check REC status
kubectl get rec -n redis-enterprise --context=region1-new
kubectl describe rec <rec-name> -n redis-enterprise --context=region1-new

# Check REAADB status
kubectl get reaadb -n redis-enterprise --context=region1-new
kubectl describe reaadb <reaadb-name> -n redis-enterprise --context=region1-new

# Check operator logs
kubectl logs -n redis-enterprise -l name=redis-enterprise-operator --context=region1-new
```

### Use Troubleshooting Scripts
```bash
cd deploy
bash scripts/troubleshoot-crdb.sh values-region1.yaml
bash scripts/troubleshoot-reaadb-pending.sh values-region1.yaml
```

See [deploy/CRDB-TROUBLESHOOTING.md](deploy/CRDB-TROUBLESHOOTING.md) for detailed troubleshooting.

## Project Structure

```
eks-dual-region-active-active/
├── main.tf                        # Dual-region infrastructure
├── variables.tf                   # Configuration variables
├── terraform.tfvars               # Your configuration (gitignored)
├── terraform.tfvars.example       # Configuration template
├── provider.tf                    # AWS provider configs
├── outputs.tf                     # Terraform outputs
├── .gitignore                     # Git ignore rules
├── README.md                      # This file
├── DEPLOYMENT-GUIDE.md            # Complete deployment guide
├── DYNAMIC-CONFIGURATION.md       # Dynamic configuration details
├── DELETE_RESOURCES.md            # Resource deletion guide
│
└── deploy/                        # Deployment automation
    ├── README-AUTOMATED-DEPLOYMENT.md  # Detailed deployment steps
    ├── CRDB-TROUBLESHOOTING.md         # CRDB troubleshooting
    ├── REAADB-PENDING-TROUBLESHOOTING.md  # REAADB troubleshooting
    ├── values-region1.yaml             # Generated config for region 1
    ├── values-region2.yaml             # Generated config for region 2
    │
    ├── templates/                      # YAML templates
    │   ├── rerc.yaml.tpl              # RERC template
    │   └── reaadb.yaml.tpl            # REAADB template
    │
    └── scripts/                        # Deployment scripts
        ├── generate-values.sh          # Generate config from tfvars
        ├── deploy-all.sh               # Master orchestration script
        ├── validate-rec.sh             # Validate REC deployment
        ├── validate-ingress.sh         # Validate ingress resources
        ├── validate-dns.sh             # Validate DNS resolution
        ├── validate-rerc.sh            # Validate RERC status
        ├── validate-reaadb.sh          # Validate REAADB deployment
        ├── validate-replication.sh     # Test bidirectional replication
        ├── setup-admission.sh          # Setup admission controllers
        ├── deploy-rerc.sh              # Deploy RERCs
        ├── deploy-reaadb.sh            # Deploy REAADB
        ├── create-dns-records.sh       # Create DNS records
        ├── cleanup-reaadb.sh           # Cleanup REAADB resources
        ├── troubleshoot-crdb.sh        # CRDB troubleshooting
        ├── troubleshoot-reaadb-pending.sh  # REAADB pending troubleshooting
        └── verify-rec-health.sh        # Verify REC health
```

## Cleanup

To destroy all resources:

```bash
cd redis-enterprise-software/eks-dual-region-active-active
terraform destroy -auto-approve
```

The destroy process automatically:
1. Deletes DNS records
2. Deletes custom resources (REAADB, RERC, REDB, REC) in correct order
3. Deletes Kubernetes resources
4. Deletes EKS clusters
5. Deletes VPCs and networking

**Total cleanup time:** ~15-20 minutes

See [DELETE_RESOURCES.md](./DELETE_RESOURCES.md) for detailed deletion information.

## Cost Estimate

**Approximate monthly cost:** ~$1,600-2,000 (both regions)

- 2x EKS clusters: ~$146/month
- 2x 3 m5.xlarge nodes: ~$900/month
- 2x EBS volumes: ~$100/month
- 2x NAT Gateways: ~$90/month
- Data transfer: Variable

## Support

This deployment uses the core `redis-enterprise-eks` module located at:
`../modules/redis-enterprise-eks/`

For issues or questions:
- Check [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md)
- Review [deploy/CRDB-TROUBLESHOOTING.md](./deploy/CRDB-TROUBLESHOOTING.md)
- Check operator logs: `kubectl logs -n redis-enterprise -l name=redis-enterprise-operator`

