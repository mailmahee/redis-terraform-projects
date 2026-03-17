# Complete Deployment Guide

**End-to-End Deployment of Redis Enterprise Active-Active**

---

## 🎯 Overview

This guide walks you through the complete deployment process from infrastructure to application using the automated workflow.

---

## 📋 Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl installed
- yq installed (for Redis Monitoring UI)

---

## 🚀 Complete Deployment Workflow

### **Phase 1: Infrastructure Deployment**

```bash
cd redis-enterprise-software/eks-dual-region-active-active

# 1. Configure Terraform
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# Minimum required changes:
# - project_prefix = "your-company"
# - owner = "your-name"
# - aws_profile = "your-aws-profile"

# 2. Deploy infrastructure
terraform init
terraform plan
terraform apply
```

**What happens:**
- ✅ Creates VPCs in both regions
- ✅ Creates EKS clusters with node groups
- ✅ Sets up VPC peering
- ✅ Configures Route53 private DNS
- ✅ Deploys Redis Enterprise Operator
- ✅ Deploys Redis Enterprise Clusters (REC)
- ✅ **Auto-generates `post-deployment/config.env`**

---

### **Phase 2: Validation**

```bash
# Validate configuration
./validate-config.sh
```

**Expected output:**
```
==========================================================================
  Configuration Validation
==========================================================================

📋 Checking configuration files...

1. Validating PROJECT_PREFIX...
   ✅ MATCH: terraform.tfvars (acme) = config.env (acme)

2. Validating required variables...
   ✅ PROJECT_PREFIX = acme
   ✅ AWS_REGION1 = us-east-1
   ✅ AWS_REGION2 = us-east-2
   ...

✅ VALIDATION PASSED!
```

---

### **Phase 3: Application Deployment**

```bash
# Navigate to post-deployment directory
cd post-deployment

# Load configuration
source config.env

# Deploy all components
./deploy-all.sh
```

**Deployment menu:**
```
1. Deploy Active-Active CRDB only
2. Deploy Prometheus Monitoring only
3. Deploy Automated Backups only
4. Deploy Redis Monitoring UI only
5. Deploy ALL components (recommended)
6. Exit
```

**Select option 5** for complete deployment.

---

## 📦 What Gets Deployed

### **Infrastructure (Terraform)**
1. ✅ VPC in us-east-1 (10.1.0.0/16)
2. ✅ VPC in us-east-2 (10.2.0.0/16)
3. ✅ EKS Cluster in us-east-1
4. ✅ EKS Cluster in us-east-2
5. ✅ VPC Peering between regions
6. ✅ Route53 Private Hosted Zone
7. ✅ Redis Enterprise Operator (both regions)
8. ✅ Redis Enterprise Cluster (both regions)

### **Application (Post-Deployment)**
1. ✅ **Active-Active CRDB** - Multi-region database
2. ✅ **Prometheus Monitoring** - Metrics collection
3. ✅ **Automated Backups** - S3-based backups
4. ✅ **Redis Monitoring UI** - Web-based dashboard

---

## 🔍 Verification

### **Check Infrastructure**

```bash
# Verify EKS clusters
aws eks list-clusters --region us-east-1
aws eks list-clusters --region us-east-2

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name <cluster-name> --alias region1
aws eks update-kubeconfig --region us-east-2 --name <cluster-name> --alias region2

# Check Redis Enterprise Clusters
kubectl get rec -n redis-enterprise --context region1
kubectl get rec -n redis-enterprise --context region2
```

### **Check Application**

```bash
# Check Active-Active database
kubectl get reaadb -n redis-enterprise --context region1
kubectl get reaadb -n redis-enterprise --context region2

# Check database status
kubectl get reaadb <crdb-name> -n redis-enterprise --context region1 -o yaml

# Check monitoring
kubectl get servicemonitor -n redis-enterprise --context region1

# Check Redis Monitoring UI
kubectl get deployment redis-monitoring-ui -n redis-enterprise --context region1
```

---

## 🎨 Configuration Files

### **terraform.tfvars** (You Edit)
```hcl
project_prefix = "acme"
region1        = "us-east-1"
region2        = "us-east-2"
aws_profile    = "default"
owner          = "your-name"
```

### **post-deployment/config.env** (Auto-Generated)
```bash
export PROJECT_PREFIX="acme"
export AWS_REGION1="us-east-1"
export AWS_REGION2="us-east-2"
export REGION1_CLUSTER_NAME="acme-r1-rec-us-east-1"
export REGION2_CLUSTER_NAME="acme-r2-rec-us-east-2"
export CRDB_NAME="acme-crdb-production"
# ... and many more
```

---

## 🔧 Customization

### **Change Database Settings**

Edit `main.tf` (local_file resource):
```hcl
export CRDB_MEMORY="200GB"      # Increase memory
export CRDB_SHARDS="12"         # Increase shards
```

Then run:
```bash
terraform apply
cd post-deployment && source config.env
./deploy-all.sh
```

---

## 🆘 Troubleshooting

### **Problem: config.env not found**
**Solution:** Run `terraform apply` to generate it

### **Problem: Validation fails**
**Solution:** Check `project_prefix` in `terraform.tfvars`

### **Problem: REC not Running**
**Solution:** Wait for REC to be ready (check with `kubectl get rec`)

### **Problem: CRDB deployment fails**
**Solution:** Ensure both RECs are Running before deploying CRDB

---

## 📚 Documentation

- **QUICK-START.md** - Fast deployment guide
- **CONFIGURATION-GUIDE.md** - Understanding the architecture
- **AUTOMATED-WORKFLOW.md** - Detailed workflow explanation
- **README.md** - Project overview

---

## ✅ Success Criteria

After complete deployment, you should have:

1. ✅ 2 EKS clusters running
2. ✅ 2 Redis Enterprise Clusters (REC) in Running state
3. ✅ 1 Active-Active database (REAADB) in active state
4. ✅ Prometheus monitoring collecting metrics
5. ✅ S3 bucket configured for backups
6. ✅ Redis Monitoring UI accessible via port-forward

---

**You're all set! Your Redis Enterprise Active-Active deployment is complete!** 🎉

