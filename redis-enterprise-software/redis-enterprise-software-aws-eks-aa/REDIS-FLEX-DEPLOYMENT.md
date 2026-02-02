# Redis Flex Deployment Guide for AWS EKS

This guide walks you through deploying Redis Enterprise Software with **Redis Flex (Auto Tiering)** on Amazon EKS, enabling automatic tiering between RAM and flash storage (NVMe SSDs).

## 🎯 What is Redis Flex?

**Redis Flex** (formerly Redis on Flash) automatically tiers data between RAM and flash storage:
- **Hot data** stays in RAM for maximum performance
- **Warm/cold data** automatically moves to flash storage
- **Transparent** to applications - standard Redis commands work
- **Cost savings** - Flash storage is ~75% cheaper than RAM

### Example Use Case
With the included `max-memory-db.yaml`:
- **Total capacity**: 35GB (3.5GB RAM + 31.5GB Flash)
- **250 shards** for high throughput
- **Cost savings**: ~70-80% vs 35GB all-RAM database

---

## 📋 Prerequisites

### 1. AWS Requirements
- AWS Account with credentials configured (`aws configure`)
- Terraform >= 1.0
- kubectl >= 1.23
- AWS CLI configured

### 2. Instance Requirements
**CRITICAL**: Redis Flex requires EC2 instances with **local NVMe SSDs**. EBS volumes do NOT work.

Supported instance types:
- **i3 family**: i3.xlarge, i3.2xlarge, i3.4xlarge, i3.8xlarge
  - i3.xlarge: 30.5GB RAM, 950GB NVMe SSD (~$0.312/hr)
- **i4i family**: i4i.xlarge, i4i.2xlarge, i4i.4xlarge (AWS Nitro)
  - i4i.xlarge: 32GB RAM, 468GB NVMe SSD (~$0.333/hr)

### 3. Local Tools
```bash
# Verify you have required tools
terraform --version
kubectl version --client
aws --version
```

---

## 🚀 Deployment Steps

### Step 1: Configure Terraform

```bash
# Navigate to project directory
cd redis-enterprise-software-aws-eks

# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
```

**Edit `terraform.tfvars`** with your values:

```hcl
#==============================================================================
# REQUIRED: Update these values
#==============================================================================
user_prefix  = "your-name"              # Your unique identifier
cluster_name = "redis-ent-eks"          # Cluster name
owner        = "your-name"              # Owner tag
aws_region   = "us-west-2"              # Your AWS region

# Redis Enterprise credentials
redis_cluster_username = "admin@admin.com"
redis_cluster_password = "YourSecurePassword123"  # Alphanumeric only

#==============================================================================
# CRITICAL: Redis Flex Configuration (already set in .example)
#==============================================================================
# Instance type with NVMe SSDs
node_instance_types = ["i3.xlarge"]     # Required for Redis Flex

# Increase memory allocation for i3.xlarge instances
redis_cluster_memory = "16Gi"           # i3.xlarge has 30.5GB RAM

# Enable Redis Flex at cluster level
enable_redis_flex           = true      # Enable Redis Flex
redis_flex_storage_class    = "local-scsi"
redis_flex_flash_disk_size  = "400G"    # Flash per node (max ~850G for i3.xlarge)
redis_flex_storage_driver   = "speedb"  # speedb (recommended) or rocksdb

# Enable Redis Flex for sample database
sample_db_enable_redis_flex = true
sample_db_rof_ram_size      = "10MB"    # Min 10% of sample_db_memory
```

### Step 2: Deploy Infrastructure with Terraform

```bash
# Initialize Terraform
terraform init

# Review what will be created
terraform plan

# Deploy (takes ~15-20 minutes)
terraform apply
```

**What gets deployed:**
- EKS cluster (Kubernetes 1.28)
- 3x i3.xlarge worker nodes across 3 AZs
- VPC with public/private subnets
- EBS CSI driver for system storage
- Redis Enterprise Operator (v8.0.2-2)

### Step 3: Configure kubectl

```bash
# Configure kubectl to access your cluster
aws eks update-kubeconfig --region us-west-2 --name <user-prefix>-redis-ent-eks

# Verify cluster access
kubectl get nodes
```

**Expected output:**
```
NAME                                         STATUS   ROLES    AGE
ip-10-0-1-xxx.us-west-2.compute.internal     Ready    <none>   5m
ip-10-0-2-xxx.us-west-2.compute.internal     Ready    <none>   5m
ip-10-0-3-xxx.us-west-2.compute.internal     Ready    <none>   5m
```

### Step 4: Deploy Local Storage Provisioner

**CRITICAL**: This step must be completed BEFORE deploying Redis Enterprise cluster with Flex enabled.

```bash
# Deploy the local NVMe storage provisioner
kubectl apply -f k8s-manifests/local-storage-provisioner.yaml
```

**Verify deployment:**
```bash
# Check provisioner pods are running
kubectl get pods -n local-storage -l app=local-volume-provisioner

# Expected: 3 pods running (one per node)
NAME                              READY   STATUS    RESTARTS   AGE
local-volume-provisioner-xxxxx    1/1     Running   0          2m
local-volume-provisioner-yyyyy    1/1     Running   0          2m
local-volume-provisioner-zzzzz    1/1     Running   0          2m

# Verify NVMe devices were discovered and mounted
kubectl logs -n local-storage -l app=local-volume-provisioner --tail=50

# Check for PersistentVolumes created from NVMe devices
kubectl get pv | grep local-scsi

# Expected: PVs for each NVMe device discovered
NAME              CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      STORAGECLASS
local-pv-xxxxx    850Gi      RWO            Retain           Available   local-scsi
local-pv-yyyyy    850Gi      RWO            Retain           Available   local-scsi
local-pv-zzzzz    850Gi      RWO            Retain           Available   local-scsi
```

**Troubleshooting:**
```bash
# If no PVs appear, check init container logs
kubectl logs -n local-storage <pod-name> -c discover-nvme

# SSH into a worker node to verify NVMe devices
# Get node name
kubectl get nodes
# Start a debug pod
kubectl debug node/<node-name> -it --image=ubuntu
# Inside the pod:
lsblk
ls -la /dev/nvme*
```

### Step 5: Wait for Redis Enterprise Cluster to Deploy

The Redis Enterprise cluster is deployed automatically by Terraform.

```bash
# Watch cluster creation (takes ~5-8 minutes)
kubectl get rec -n redis-enterprise -w

# Expected progression:
# STATE: BootstrappingFirstPod -> Initializing -> Running
```

**Verify cluster is ready:**
```bash
kubectl get rec -n redis-enterprise
```

**Expected output:**
```
NAME            NODES   VERSION    STATE     SPEC STATUS   LICENSE STATE
redis-ent-eks   3       8.0.2-41   Running   Valid         Valid
```

**Verify Redis Flex is enabled:**
```bash
kubectl describe rec redis-ent-eks -n redis-enterprise | grep -A 10 "Redis On Flash"
```

**Expected output:**
```
  Redis On Flash Spec:
    Big Store Driver:     speedb
    Enabled:              true
    Flash Disk Size:      400G
    Storage Class Name:   local-scsi
```

### Step 6: Verify Sample Database with Redis Flex

The Terraform deployment creates a sample database with Redis Flex enabled.

```bash
# Check database status
kubectl get redb -n redis-enterprise

# Expected output:
NAME   VERSION   PORT    CLUSTER         SHARDS   STATUS   SPEC STATUS   AGE
demo   7.2.4     12000   redis-ent-eks   1        active   Valid         3m
```

**Verify Redis Flex is enabled for database:**
```bash
kubectl get redb demo -n redis-enterprise -o yaml | grep -A 5 "isRof\|rofRamSize"
```

**Expected output:**
```yaml
  isRof: true
  rofRamSize: 10MB
  memorySize: 100MB
```

### Step 7: Create Large Redis Flex Database (Optional)

Deploy the high-capacity Redis Flex database for testing:

```bash
# Create password secret
kubectl apply -f max-db-password.yaml

# Create large Redis Flex database (35GB total: 3.5GB RAM + 31.5GB Flash)
kubectl apply -f max-memory-db.yaml

# Watch database creation
kubectl get redb max-db -n redis-enterprise -w
```

**Verify large database:**
```bash
kubectl get redb max-db -n redis-enterprise

# Expected:
NAME     VERSION   PORT    CLUSTER         SHARDS   STATUS   SPEC STATUS   AGE
max-db   7.2.4     12001   redis-ent-eks   250      active   Valid         5m
```

---

## 🔍 Testing Redis Flex

### Access Redis Enterprise UI

**Terminal 1** (keep running):
```bash
kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443
```

**Browser:**
1. Open https://localhost:8443
2. Accept self-signed certificate warning
3. Login:
   - Username: `admin@admin.com`
   - Password: Your configured password

**In the UI, verify:**
- Navigate to **Databases** → Select database
- Check **Memory** section shows:
  - **RAM**: 3.5GB (for max-db)
  - **Flash**: 31.5GB (for max-db)
  - **RAM Hit Rate**: Shows percentage of requests served from RAM

### Test Database with redis-cli

**Terminal 2** (keep running):
```bash
# Port-forward database
kubectl port-forward -n redis-enterprise svc/demo 12000:12000

# For max-db:
kubectl port-forward -n redis-enterprise svc/max-db 12001:12001
```

**Terminal 3**:
```bash
# Connect to demo database
redis-cli -h localhost -p 12000 -a admin

# Or connect to max-db
redis-cli -h localhost -p 12001 -a admin

# Test basic operations
SET key1 "value1"
GET key1

# Write large dataset to test tiering
for i in {1..100000}; do
  redis-cli -h localhost -p 12001 -a admin SET "key:$i" "value:$i"
done

# Monitor memory usage in UI
# You should see data automatically tiering to flash
```

### Monitor Redis Flex Tiering

```bash
# Get cluster metrics
kubectl exec -it redis-ent-eks-0 -n redis-enterprise -c redis-enterprise-node -- rladmin status

# Check database statistics
kubectl exec -it redis-ent-eks-0 -n redis-enterprise -c redis-enterprise-node -- rladmin info db max-db

# Look for:
# - RAM hit ratio (should be high for hot data)
# - Flash usage
# - Eviction statistics
```

---

## 📊 Verifying Redis Flex Performance

### Expected Behavior

1. **Initial writes**: All data goes to RAM first
2. **As RAM fills**: Less frequently accessed data moves to flash
3. **RAM hit rate**: Should be 90%+ for typical workloads
4. **Latency**:
   - RAM hits: Sub-millisecond
   - Flash hits: 1-5ms (still very fast)

### Performance Tests

```bash
# Install redis-benchmark (if not already installed)
# On macOS: brew install redis
# On Ubuntu: apt-get install redis-tools

# Run benchmark against max-db
redis-benchmark -h localhost -p 12001 -a admin -n 100000 -d 1024 -t set,get -c 50

# Expected results:
# SET: 40,000-60,000 ops/sec
# GET: 80,000-120,000 ops/sec (depends on RAM hit rate)
```

---

## 🔧 Troubleshooting

### Issue: Redis cluster pods stuck in Pending

**Check PVCs:**
```bash
kubectl get pvc -n redis-enterprise
```

**Check PV availability:**
```bash
kubectl get pv | grep local-scsi
```

**Solution:** Ensure local storage provisioner created PVs from NVMe devices (see Step 4)

### Issue: Database fails to create with "redisOnFlash not available"

**Check cluster Redis Flex config:**
```bash
kubectl get rec redis-ent-eks -n redis-enterprise -o yaml | grep -A 10 redisOnFlashSpec
```

**Solution:**
1. Ensure cluster has `enable_redis_flex = true` in terraform.tfvars
2. Run `terraform apply` to update cluster
3. Wait for cluster to reconcile

### Issue: No NVMe devices found

**Check instance type:**
```bash
kubectl get nodes -o wide

# Verify instance type shows i3.xlarge or i4i.xlarge
```

**Verify NVMe devices on node:**
```bash
# Debug a node
kubectl debug node/<node-name> -it --image=ubuntu

# Inside debug pod:
lsblk
ls -la /dev/nvme*

# Expected: /dev/nvme0n1 (root EBS), /dev/nvme1n1 (local NVMe)
```

**Solution:** Ensure `node_instance_types = ["i3.xlarge"]` in terraform.tfvars, then `terraform apply`

### Issue: High flash latency

**Check flash storage driver:**
```bash
kubectl get rec redis-ent-eks -n redis-enterprise -o yaml | grep bigStoreDriver
```

**Solution:** Should be `speedb` (faster than `rocksdb`)

### Issue: Low RAM hit rate

**Possible causes:**
1. **RAM too small**: Increase `rofRamSize` (min 10% of total memory)
2. **Working set too large**: More data is hot than fits in RAM
3. **Random access pattern**: No locality of reference

**Check database config:**
```bash
kubectl get redb max-db -n redis-enterprise -o yaml | grep -E "memorySize|rofRamSize"
```

---

## 🧹 Cleanup

When done testing:

```bash
# Delete databases
kubectl delete -f max-memory-db.yaml
kubectl delete -f max-db-password.yaml

# Destroy infrastructure (WARNING: Deletes everything)
terraform destroy

# This will remove:
# - All EKS resources
# - VPC and networking
# - All data (local NVMe data is ephemeral)
```

**Cost savings tip:** If keeping cluster overnight, stop it to save money:
```bash
# Scale node group to 0
aws eks update-nodegroup-config \
  --cluster-name <user-prefix>-redis-ent-eks \
  --nodegroup-name <user-prefix>-redis-ent-eks-node-group \
  --scaling-config desiredSize=0,minSize=0,maxSize=6

# Scale back up when ready
aws eks update-nodegroup-config \
  --cluster-name <user-prefix>-redis-ent-eks \
  --nodegroup-name <user-prefix>-redis-ent-eks-node-group \
  --scaling-config desiredSize=3,minSize=3,maxSize=6
```

---

## 💰 Cost Comparison

### Redis Flex (35GB database)
- **Configuration**: 3.5GB RAM + 31.5GB Flash
- **Instance cost**: 3x i3.xlarge = ~$675/month
- **Total capacity**: 35GB
- **Cost per GB**: ~$19/month

### All-RAM (35GB database)
- **Configuration**: 35GB RAM
- **Instance cost**: 3x r6i.2xlarge = ~$1,200/month
- **Total capacity**: 35GB
- **Cost per GB**: ~$34/month

**Savings with Redis Flex: ~44% for this configuration**

---

## 📚 Additional Resources

- [Redis Flex Documentation](https://redis.io/docs/latest/operate/kubernetes/re-clusters/redis-flex/)
- [Redis on Flash Overview](https://redis.io/blog/redis-enterprise-flash/)
- [Local Storage Provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner)
- [AWS EC2 Instance Types with NVMe](https://aws.amazon.com/ec2/instance-types/)

---

## ✅ Quick Reference

### Key Files
- `terraform.tfvars` - Your configuration (create from .example)
- `k8s-manifests/local-storage-provisioner.yaml` - NVMe provisioner
- `max-memory-db.yaml` - Large Redis Flex database (35GB)
- `max-db-password.yaml` - Database password secret

### Key Commands
```bash
# Check cluster status
kubectl get rec -n redis-enterprise

# Check databases
kubectl get redb -n redis-enterprise

# Check NVMe storage
kubectl get pv | grep local-scsi

# Access UI
kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443

# Access database
kubectl port-forward -n redis-enterprise svc/max-db 12001:12001
redis-cli -h localhost -p 12001 -a admin
```

### Instance Costs (us-west-2)
- **i3.xlarge**: ~$0.312/hr = ~$225/month
- **i4i.xlarge**: ~$0.333/hr = ~$240/month
- **EKS control plane**: ~$73/month
- **Total (3x i3.xlarge)**: ~$775-825/month

---

**Questions or issues?** Check the troubleshooting section or review the main README.md
