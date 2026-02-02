# Redis Flex (Auto Tiering) - Quick Start Guide

## ✨ FULLY AUTOMATED DEPLOYMENT

This repository now supports **one-command** switching between RAM-only and Redis Flex modes!

---

## 🚀 Deployment Modes

### MODE 1: RAM-ONLY (Default)

**Best for:** Standard deployments, smaller datasets, simplicity

**What you get:**
- EBS GP3 storage only
- t3.xlarge instances (or any standard instance type)
- Simple configuration
- Lower cost for small-medium datasets

**How to deploy:**
```bash
# 1. Copy example config
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars - fill in your credentials
# (Keep default RAM-only settings)

# 3. Deploy
terraform init
terraform apply
```

**No changes needed!** Default configuration is RAM-only.

---

### MODE 2: REDIS FLEX (Auto Tiering)

**Best for:** Large datasets, cost optimization, production workloads

**What you get:**
- Automatic tiering between RAM (hot data) and NVMe flash (warm/cold data)
- 70-80% cost savings vs RAM-only for large datasets
- i3.2xlarge instances with 1.9TB NVMe SSDs
- **Everything automated** - NVMe discovery, storage classes, provisioner deployment

**How to deploy:**
```bash
# 1. Copy example config
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars:
#    a. UNCOMMENT the i3.2xlarge instance type (line ~60)
#    b. UNCOMMENT all Redis Flex settings (lines ~140-148)

# 3. Deploy - everything else is automatic!
terraform init
terraform apply
```

**That's it!** Terraform automatically:
- ✅ Validates you're using i3/i4i instances
- ✅ Deploys NVMe storage provisioner
- ✅ Discovers and mounts NVMe devices
- ✅ Creates local-scsi storage class
- ✅ Configures Redis cluster with Flash storage
- ✅ Creates databases with automatic tiering

---

## 📝 What Changed in terraform.tfvars

### RAM-ONLY (Default - Lines 49-50)
```hcl
node_instance_types = ["t3.xlarge"]  # Standard instance
```

```hcl
enable_redis_flex = false  # RAM-only mode
```

### REDIS FLEX (Lines 60-61, 140-148)
```hcl
# UNCOMMENT these 2 lines in EKS NODE GROUP section:
# node_instance_types = ["i3.2xlarge"]  # NVMe instance
# node_disk_size      = 100              # EBS for OS only

# UNCOMMENT these 7 lines in REDIS FLEX CONFIG section:
# enable_redis_flex              = true
# redis_flex_storage_class       = "local-scsi"
# redis_flex_flash_disk_size     = "800G"
# redis_flex_storage_driver      = "speedb"
# sample_db_enable_redis_flex    = true
# sample_db_rof_ram_size         = "12GB"
# sample_db_memory               = "120GB"
```

---

## 🔍 Verification After Deployment

### Check cluster has Redis Flex enabled:
```bash
kubectl get rec redis-ent-eks -n redis-enterprise -o yaml | grep -A 5 redisOnFlashSpec
```

Expected output:
```yaml
redisOnFlashSpec:
  bigStoreDriver: speedb
  enabled: true
  flashDiskSize: 800G
  storageClassName: local-scsi
```

### Check NVMe volumes are provisioned:
```bash
kubectl get pv | grep local-scsi
```

Expected: 3x 1740Gi volumes (one per node)

### Check database has Redis Flex:
```bash
kubectl get redb demo -n redis-enterprise -o yaml | grep -E "isRof|rofRamSize|memorySize"
```

Expected output:
```yaml
isRof: true
memorySize: 120GB
rofRamSize: 12GB
```

---

## ⚙️ How It Works

### 1. **Instance Type Validation** (main.tf:29-67)
Terraform validates that when `enable_redis_flex=true`, you're using i3/i4i instances:
```hcl
lifecycle {
  precondition {
    condition     = !var.enable_redis_flex || local.using_flex_instance
    error_message = "Redis Flex requires i3.* or i4i.* instance types..."
  }
}
```

### 2. **Automatic NVMe Provisioner** (modules/local_storage_provisioner/)
When `enable_redis_flex=true`, Terraform automatically deploys the local storage provisioner:
- Runs as DaemonSet on all nodes
- Discovers NVMe devices (`/dev/nvme*n1`)
- Formats with ext4
- Mounts at `/mnt/disks/`
- Creates PersistentVolumes with `local-scsi` storage class

### 3. **Conditional Redis Configuration**
Cluster and database configurations automatically include Redis Flex settings when enabled:

**Cluster** (modules/redis_cluster/main.tf:78-86):
```hcl
%{if var.enable_redis_flex~}
  redisOnFlashSpec:
    enabled: true
    bigStoreDriver: ${var.redis_flex_storage_driver}
    storageClassName: "${var.redis_flex_storage_class}"
    flashDiskSize: ${var.redis_flex_flash_disk_size}
%{endif~}
```

**Database** (modules/redis_database/main.tf:21):
```hcl
${var.enable_redis_flex ? "
  isRof: true
  rofRamSize: ${var.rof_ram_size}" : ""}
```

### 4. **Dependency Chain**
```
EKS Cluster
  → Node Group (i3.2xlarge)
    → EBS CSI Driver
      → Local Storage Provisioner (if flex enabled)
        → Redis Operator
          → Redis Cluster (with redisOnFlashSpec)
            → Redis Database (with isRof)
```

---

## 🎯 Memory Configuration for Redis Flex

### Important Rule: RAM must be ≥10% of Total Memory

**Example configurations:**

| Total Memory | RAM (rofRamSize) | Flash | Valid? |
|-------------|------------------|-------|--------|
| 120GB | 12GB (10%) | 108GB | ✅ Yes |
| 200GB | 20GB (10%) | 180GB | ✅ Yes |
| 500GB | 50GB (10%) | 450GB | ✅ Yes |
| 100GB | 10GB (10%) | 90GB | ❌ No - Need 10GB minimum RAM |
| 110GB | 10GB (9%) | 100GB | ❌ No - RAM < 10% |

**Calculator:**
- Want 100GB flash? → Total = 100/0.9 = 111GB, RAM = 11.1GB
- Want 500GB flash? → Total = 500/0.9 = 556GB, RAM = 55.6GB

---

## 💰 Cost Comparison

### RAM-ONLY (t3.xlarge - 16GB RAM)
- EKS control plane: ~$73/month
- 3x t3.xlarge: ~$300/month
- EBS gp3 (300GB): ~$25/month
- **Total: ~$400/month**
- **Usable Redis memory: ~36GB** (3 nodes × 12GB per node)

### REDIS FLEX (i3.2xlarge - 61GB RAM + 1.9TB NVMe)
- EKS control plane: ~$73/month
- 3x i3.2xlarge: ~$675/month
- EBS gp3 (300GB): ~$25/month
- **Total: ~$775/month**
- **Usable Redis memory: ~360GB total!** (e.g., 36GB RAM + 324GB flash per cluster)

**Result: 10x more storage for 2x the cost = 5x better cost efficiency!**

---

## 🔄 Switching Between Modes

### RAM → Flex:
1. Backup your data
2. Edit terraform.tfvars (uncomment Flex settings)
3. `terraform apply`
4. Data will need to be reloaded

### Flex → RAM:
1. Backup your data
2. Edit terraform.tfvars (comment Flex settings, change to t3.xlarge)
3. `terraform apply`
4. Data will need to be reloaded

**Note:** Cannot convert in-place. Requires cluster recreation.

---

## ❓ FAQ

**Q: Do I need to manually apply the NVMe provisioner?**
A: No! It's now fully automated via Terraform.

**Q: Can I use Redis Flex with EBS volumes?**
A: No. Redis Flex requires local NVMe SSDs (i3/i4i instances only).

**Q: What if I enable Flex but use t3.xlarge?**
A: Terraform will fail with a validation error explaining you need i3/i4i instances.

**Q: Can I use different instance types in the same cluster?**
A: Not recommended. Stick to one instance type for consistency.

**Q: What's the minimum database size for Redis Flex?**
A: RAM portion must be ≥100MB (Redis minimum), and ≥10% of total memory.

---

## 📚 Additional Resources

- [Redis Flex Documentation](https://redis.io/docs/latest/operate/kubernetes/re-clusters/redis-flex/)
- [AWS i3 Instance Pricing](https://aws.amazon.com/ec2/instance-types/i3/)
- [Redis Enterprise Kubernetes Documentation](https://github.com/RedisLabs/redis-enterprise-k8s-docs)

---

**🎉 Enjoy your fully automated Redis Flex deployment!**
