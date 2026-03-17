# Quick Start Guide

**Deploy Redis Enterprise Active-Active in 2 Simple Steps**

---

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- kubectl installed

---

## 🚀 Step-by-Step Deployment

### **Step 1: Configure Terraform**

```bash
cd redis-enterprise-software/eks-dual-region-active-active

# Copy the example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit the configuration
vim terraform.tfvars
```

**Minimum required changes:**
```hcl
project_prefix = "acme"        # Your company/project name
owner          = "your_name"   # Your name
aws_profile    = "your_profile" # Your AWS CLI profile
```

---

### **Step 2: Deploy Everything**

```bash
# Deploy infrastructure (this auto-generates config.env)
terraform init
terraform plan
terraform apply

# Validate the generated configuration
./validate-config.sh

# Deploy Active-Active database
cd post-deployment
source config.env
./deploy-all.sh
```

---

## ✨ What Happens Automatically

When you run `terraform apply`:

1. ✅ **Creates AWS infrastructure** (VPCs, EKS clusters, etc.)
2. ✅ **Auto-generates `post-deployment/config.env`** with all the correct values
3. ✅ **Outputs next steps** for you to follow

**No manual config.env editing needed!** 🎉

---

## 📋 What Gets Created

### **Infrastructure (Terraform)**
- ✅ 2 VPCs (one per region)
- ✅ 2 EKS clusters with node groups
- ✅ VPC peering between regions
- ✅ Route53 private hosted zone
- ✅ IAM roles and security groups
- ✅ **Auto-generated `config.env`** ← New!

### **Application (Post-Deployment)**
- ✅ Redis Enterprise Operator
- ✅ Redis Enterprise Clusters (REC)
- ✅ Active-Active Database (CRDB)
- ✅ Monitoring and backups

---

## 🔍 Verification

After deployment, verify everything is working:

```bash
# Check EKS clusters
aws eks list-clusters --region us-east-1
aws eks list-clusters --region us-east-2

# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name <cluster-name> --alias region1
aws eks update-kubeconfig --region us-east-2 --name <cluster-name> --alias region2

# Check Redis Enterprise
kubectl get rec -n redis-enterprise --context region1
kubectl get rec -n redis-enterprise --context region2

# Check Active-Active database
kubectl get reaadb -n redis-enterprise --context region1
```

---

## 🎯 Key Files

| File | Purpose |
|------|---------|
| `terraform.tfvars` | **You edit this** - Infrastructure configuration |
| `post-deployment/config.env` | **Auto-generated** - Application configuration |
| `validate-config.sh` | Validates both configs are in sync |

---

## 💡 Tips

- **First time?** Start with the example values and customize gradually
- **Multiple environments?** Use different `project_prefix` values
- **Need help?** See `CONFIGURATION-GUIDE.md` for detailed explanations

---

## 🆘 Troubleshooting

**Problem:** `config.env` not generated  
**Solution:** Run `terraform apply` - it creates the file automatically

**Problem:** Validation fails  
**Solution:** Check that `project_prefix` in `terraform.tfvars` matches

**Problem:** Deployment fails  
**Solution:** Check AWS credentials and quotas

---

## 📚 Next Steps

- Read `CONFIGURATION-GUIDE.md` to understand the two-layer architecture
- See `REFACTORING-GUIDE.md` for details on the generic codebase
- Check `GENERIC-CODEBASE-SUMMARY.md` for a complete overview

---

**Ready to deploy? Let's go!** 🚀

