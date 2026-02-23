# Redis Enterprise on AWS EKS - Single Region

## Overview

This is a **wrapper** that deploys the `redis-enterprise-eks` core module in a single AWS region.

This wrapper provides:
- ✅ Provider configuration for standalone deployment
- ✅ All the functionality of the core module
- ✅ Simple, straightforward deployment

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Single AWS Region (e.g., us-east-1)                    │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │  VPC (10.0.0.0/16)                                 │ │
│  │                                                     │ │
│  │  ┌──────────────────────────────────────────────┐  │ │
│  │  │  EKS Cluster                                 │  │ │
│  │  │  - 3 worker nodes (m5.xlarge)                │  │ │
│  │  │  - Redis Enterprise Operator                 │  │ │
│  │  │  - Redis Enterprise Cluster (3 nodes)        │  │ │
│  │  │  - Sample Database (optional)                │  │ │
│  │  └──────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Quick Start

### 1. Configure

```bash
cd redis-enterprise-software/eks-single-region
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
user_prefix = "your-prefix"
owner = "your-name"
redis_cluster_password = "YourSecurePassword123"
aws_region = "us-east-1"  # or your preferred region
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

**Deployment time:** ~15-20 minutes

### 3. Verify

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name your-prefix-redis-enterprise

# Check Redis Enterprise Cluster
kubectl get rec -n redis-enterprise
kubectl get pods -n redis-enterprise
```

## What Gets Deployed

- **VPC** with public and private subnets across multiple AZs
- **EKS Cluster** with managed node group
- **Redis Enterprise Operator** (Kubernetes operator)
- **Redis Enterprise Cluster** (REC) with 3 nodes
- **Sample Database** (optional, for testing)
- **EBS CSI Driver** for persistent storage
- **Bastion Host** (optional, for SSH access)

## Configuration

See `terraform.tfvars.example` for all available options.

Key variables:
- `aws_region` - AWS region to deploy to
- `user_prefix` - Prefix for all resource names
- `redis_cluster_password` - Admin password for Redis Enterprise
- `create_sample_database` - Whether to create a test database
- `create_bastion` - Whether to create a bastion host

## Cost Estimate

**Approximate monthly cost:** ~$800-1,000

- EKS cluster: ~$73/month
- 3x m5.xlarge nodes: ~$450/month
- EBS volumes: ~$50/month
- NAT Gateway: ~$45/month (per AZ)
- Data transfer: Variable

## Cleanup

```bash
terraform destroy
```

## Next Steps

After deployment:
1. Access the Redis Enterprise UI (see outputs for instructions)
2. Create additional databases as needed
3. Deploy applications to use Redis
4. Configure monitoring and backups

## Support

This wrapper uses the core `redis-enterprise-eks` module located at:
`../modules/redis-enterprise-eks/`

For issues or questions, refer to the core module documentation.

