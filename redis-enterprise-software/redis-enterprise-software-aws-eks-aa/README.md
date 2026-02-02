# Redis Enterprise Software on AWS EKS

Deploy a production-ready Redis Enterprise Software cluster on Amazon EKS (Elastic Kubernetes Service) with automated operator deployment, persistent storage, and high availability across availability zones.

## 🔥 **NEW: Redis Flex (Auto Tiering) Support**

**Want to store TBs of data at a fraction of the cost?** See **[REDIS-FLEX-DEPLOYMENT.md](REDIS-FLEX-DEPLOYMENT.md)** for complete Redis Flex deployment guide.

Redis Flex automatically tiers data between RAM and flash storage (NVMe SSDs):
- 💰 **70-80% cost savings** vs all-RAM configuration
- 📈 **Store more data** using flash as RAM extension
- 🚀 **Automatic tiering** based on access patterns
- 🔧 **Simple deployment** with automated script: `./deploy-redis-flex.sh`

## 🚀 Quick Start

### 1. Prerequisites
- **AWS Account** with credentials configured (`aws configure`)
- **Terraform** >= 1.0
- **kubectl** >= 1.23
- **AWS CLI** configured

### 2. Deploy in 3 Steps

```bash
# 1. Clone and configure
cd redis-enterprise-software-aws-eks
cp terraform.tfvars.example terraform.tfvars

# 2. Edit terraform.tfvars (see Configuration section)
# Required: user_prefix, owner, redis_cluster_username, redis_cluster_password

# 3. Deploy
terraform init
terraform plan
terraform apply
```

### 3. Post-Deployment

Deployment takes ~10-15 minutes. See **Getting Started After Deployment** section below for detailed access instructions.

---

## 📋 Getting Started After Deployment

After `terraform apply` completes successfully, follow these steps to verify and access your Redis Enterprise cluster.

### Step 1: Configure kubectl

```bash
# Configure kubectl to connect to your EKS cluster
aws eks update-kubeconfig --region us-west-2 --name bamos-redis-ent-eks
```

**Output:** `Updated context arn:aws:eks:us-west-2:...:cluster/bamos-redis-ent-eks in /Users/.../.kube/config`

---

### Step 2: Verify Cluster Status

```bash
# Check Redis Enterprise Cluster (REC) status
kubectl get rec -n redis-enterprise
```

**Expected Output:**
```
NAME            NODES   VERSION    STATE     SPEC STATUS   LICENSE STATE
redis-ent-eks   3       7.4.6-22   Running   Valid         Valid
```

✅ **STATE should be "Running"** - If it shows "BootstrappingFirstPod" or "Initializing", wait 2-3 minutes and check again.

```bash
# Check all pods are running
kubectl get pods -n redis-enterprise
```

**Expected Output:**
```
NAME                                             READY   STATUS    RESTARTS   AGE
redis-ent-eks-0                                  2/2     Running   0          5m
redis-ent-eks-1                                  2/2     Running   0          4m
redis-ent-eks-2                                  2/2     Running   0          3m
redis-ent-eks-services-rigger-...                1/1     Running   0          5m
redis-enterprise-operator-...                    2/2     Running   0          6m
```

✅ **All redis-ent-eks-* pods should show "2/2 Running"**

```bash
# Check database status
kubectl get redb -n redis-enterprise
```

**Expected Output:**
```
NAME   VERSION   PORT    CLUSTER         SHARDS   STATUS   SPEC STATUS   AGE
demo   7.2.4     12000   redis-ent-eks   2        active   Valid         3m
```

✅ **STATUS should be "active"**

```bash
# List all services
kubectl get svc -n redis-enterprise
```

**Expected Output:**
```
NAME                 TYPE        CLUSTER-IP       PORT(S)
demo                 ClusterIP   172.20.58.159    12000/TCP
redis-ent-eks-ui     ClusterIP   172.20.178.95    8443/TCP
...
```

---

### Step 3: Get Your Credentials

```bash
# Get REC admin password (should output: admin)
kubectl get secret redis-ent-eks -n redis-enterprise \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**Output:** `admin`

```bash
# Get database password (should output: admin)
kubectl get secret demo-password -n redis-enterprise \
  -o jsonpath='{.data.password}' | base64 -d && echo
```

**Output:** `admin`

**Default Credentials:**
- **REC Username:** `admin@admin.com`
- **REC Password:** `admin`
- **Database Password:** `admin`

---

### Step 4: Access the Redis Enterprise UI

**In Terminal 1** (keep this running):
```bash
# Port-forward the UI service
kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443
```

**Output:**
```
Forwarding from 127.0.0.1:8443 -> 8443
Forwarding from [::1]:8443 -> 8443
```

**⚠️ Keep this terminal open!** The port-forward runs in the foreground.

**In your web browser:**
1. Open: **https://localhost:8443**
2. Click "Advanced" → "Proceed to localhost (unsafe)" (self-signed certificate is expected)
3. Login with:
   - **Username:** `admin@admin.com`
   - **Password:** `admin`

✅ **You should see the Redis Enterprise dashboard!**

---

### Step 5: Access the Database and Write Keys

**In Terminal 2** (open a new terminal, keep this running):
```bash
# Port-forward the demo database service
kubectl port-forward -n redis-enterprise svc/demo 12000:12000
```

**Output:**
```
Forwarding from 127.0.0.1:12000 -> 12000
Forwarding from [::1]:12000 -> 12000
```

**⚠️ Keep this terminal open!** The port-forward runs in the foreground.

**In Terminal 3** (open a new terminal):
```bash
# Connect to Redis with redis-cli
redis-cli -h localhost -p 12000 -a admin
```

**Now write and read some keys:**
```bash
# Set a simple key
SET mykey "Hello Redis Enterprise on EKS!"

# Read it back
GET mykey
# Output: "Hello Redis Enterprise on EKS!"

# Set a counter
SET counter 100

# Increment it
INCR counter
# Output: (integer) 101

# Get the counter value
GET counter
# Output: "101"

# Set user data
SET user:1:name "Brandon"
SET user:1:email "brandon@example.com"

# Get user data
GET user:1:name
# Output: "Brandon"

# Check all keys
KEYS *
# Output: 1) "mykey" 2) "counter" 3) "user:1:name" 4) "user:1:email"

# Delete a key
DEL counter

# Exit redis-cli
exit
```

✅ **Your Redis Enterprise cluster is fully operational!**

---

### Step 6: Access from Inside the Cluster (Optional)

If you deploy applications as pods in the cluster, they can access Redis directly without port-forwarding:

**Database Service FQDN:**
```
demo.redis-enterprise.svc.cluster.local:12000
```

**Example: Test from a temporary pod**
```bash
# Start a temporary Redis CLI pod
kubectl run redis-test --image=redis:latest -n redis-enterprise --rm -it -- bash

# Inside the pod, connect to the database
redis-cli -h demo -p 12000 -a admin

# Write a key
SET from-pod "Hello from inside the cluster!"
GET from-pod

# Exit
exit
```

---

### Summary Checklist

- ✅ REC shows `STATE: Running`
- ✅ All 3 redis-ent-eks-* pods are `2/2 Running`
- ✅ Database shows `STATUS: active`
- ✅ Can login to UI at https://localhost:8443
- ✅ Can connect to database with redis-cli
- ✅ Can write and read keys successfully

**🎉 Your Redis Enterprise cluster on EKS is ready for production use!**

---

## ⚙️ Configuration

### Required Variables

```hcl
# Project Settings
user_prefix  = "your-name"           # Your unique identifier
cluster_name = "redis-ent-eks"       # Cluster name
owner        = "your-name"           # Owner tag

# AWS Configuration
aws_region = "us-west-2"

# Redis Enterprise Credentials
redis_cluster_username = "admin@admin.com"
redis_cluster_password = "YourSecurePassword123"  # Alphanumeric only, min 8 chars
```

### Optional Settings

```hcl
# Kubernetes Version
kubernetes_version = "1.28"          # 1.23 - 1.33 supported

# Worker Nodes
node_instance_types = ["t3.xlarge"]  # 16GB RAM per node
node_desired_size   = 3              # Minimum 3 for HA
node_min_size       = 3
node_max_size       = 6

# Redis Enterprise Cluster
redis_cluster_nodes  = 3             # Number of Redis nodes
redis_cluster_memory = "4Gi"         # Memory per node
redis_cluster_storage_size = "50Gi"  # Storage per node

# Sample Database
create_sample_database = true
sample_db_name         = "demo"
sample_db_port         = 12000
sample_db_memory       = "100MB"
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AWS Account                                │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │                      Amazon VPC                                │ │
│  │                                                                │ │
│  │  ┌──────────────────────────────────────────────────────────┐ │ │
│  │  │              EKS Control Plane (Managed)                  │ │ │
│  │  └──────────────────────────────────────────────────────────┘ │ │
│  │                                                                │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │ │
│  │  │   AZ-1       │  │   AZ-2       │  │   AZ-3       │        │ │
│  │  │              │  │              │  │              │        │ │
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │        │ │
│  │  │ │ Worker   │ │  │ │ Worker   │ │  │ │ Worker   │ │        │ │
│  │  │ │ Node 1   │ │  │ │ Node 2   │ │  │ │ Node 3   │ │        │ │
│  │  │ │          │ │  │ │          │ │  │ │          │ │        │ │
│  │  │ │ Redis    │ │  │ │ Redis    │ │  │ │ Redis    │ │        │ │
│  │  │ │ Pod 1    │ │  │ │ Pod 2    │ │  │ │ Pod 3    │ │        │ │
│  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │        │ │
│  │  │              │  │              │  │              │        │ │
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │        │ │
│  │  │ │ EBS Vol  │ │  │ │ EBS Vol  │ │  │ │ EBS Vol  │ │        │ │
│  │  │ │ (gp3)    │ │  │ │ (gp3)    │ │  │ │ (gp3)    │ │        │ │
│  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │        │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘        │ │
│  │                                                                │ │
│  │  ┌──────────────────────────────────────────────────────────┐ │ │
│  │  │              LoadBalancers (UI + Databases)               │ │ │
│  │  └──────────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Components:**
- **EKS Control Plane**: Managed Kubernetes master nodes (AWS-managed)
- **Worker Nodes**: EC2 instances running Redis Enterprise pods (3+ nodes)
- **Redis Enterprise Operator**: Manages cluster lifecycle via Kubernetes CRDs
- **EBS CSI Driver**: Provides persistent storage for Redis data
- **ClusterIP Services**: Internal-only access (per Redis Enterprise K8s docs)
- **Multi-AZ HA**: Rack awareness ensures pods distributed across AZs

## 🔧 What Gets Deployed

### AWS Infrastructure
1. **VPC & Networking**
   - VPC with public/private subnets across 3 AZs
   - Internet Gateway for public access
   - Route tables and subnet associations
   - Security groups for EKS cluster and nodes

2. **EKS Cluster**
   - Managed Kubernetes control plane (v1.28)
   - OIDC provider for IAM integration
   - Cluster addons: vpc-cni, coredns, kube-proxy
   - CloudWatch logging enabled

3. **EKS Node Group**
   - 3+ EC2 worker nodes (t3.xlarge by default)
   - Auto-scaling group configuration
   - Launch template with encrypted EBS volumes
   - IAM roles and policies

4. **EBS CSI Driver**
   - AWS EBS CSI driver addon
   - gp3 storage class (default)
   - IRSA (IAM Roles for Service Accounts)

### Kubernetes Resources
1. **Redis Enterprise Operator**
   - Deployed via Helm chart
   - Manages RedisEnterpriseCluster (REC) and RedisEnterpriseDatabase (REDB) CRDs
   - Automatic reconciliation and health monitoring

2. **Redis Enterprise Cluster (REC)**
   - 3-node cluster with rack awareness
   - Persistent volumes for each node
   - Admin credentials stored in Kubernetes secrets
   - ClusterIP service for UI access (port 8443)

3. **Sample Database (REDB)** - Optional
   - Redis database for testing
   - Replication enabled
   - ClusterIP service for internal database access
   - Configurable memory and persistence

## 📊 Deployment Timeline

- **EKS Cluster**: ~8-10 minutes
- **Node Group**: ~3-5 minutes
- **EBS CSI Driver**: ~1-2 minutes
- **Redis Operator**: ~1 minute
- **Redis Cluster**: ~3-5 minutes
- **Sample Database**: ~1-2 minutes
- **Total**: ~15-20 minutes

## 🔍 Management

### Useful Commands

```bash
# Configure kubectl for your cluster
aws eks update-kubeconfig --region us-west-2 --name your-prefix-redis-ent-eks

# View Redis Enterprise cluster status
kubectl get rec -n redis-enterprise
kubectl describe rec redis-ent-eks -n redis-enterprise

# View Redis databases
kubectl get redb -n redis-enterprise

# View all pods
kubectl get pods -n redis-enterprise

# View services (to get LoadBalancer endpoints)
kubectl get svc -n redis-enterprise

# View operator logs
kubectl logs -n redis-enterprise -l name=redis-enterprise-operator --tail=100

# View cluster logs
kubectl logs -n redis-enterprise -l app=redis-enterprise --tail=100

# Access Redis Enterprise pod directly
kubectl exec -it redis-ent-eks-0 -n redis-enterprise -- bash

# Get admin password
kubectl get secret redis-ent-eks-admin-credentials -n redis-enterprise \
  -o jsonpath='{.data.password}' | base64 -d
```

### Accessing the UI

**Internal Access (from pods in cluster):**
```bash
# Service FQDN
redis-ent-eks-ui.redis-enterprise.svc.cluster.local:8443
```

**Local Access (via port-forward):**
```bash
# Port-forward to your local machine
kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443

# Access at: https://localhost:8443
```

- **Username**: Your configured admin email
- **Password**: Your configured password
- **Note**: Browser will show certificate warning (self-signed cert) - this is expected

### Connecting to Databases

**From inside the cluster (applications running as pods):**
```bash
# Service FQDN format
<database-name>.<namespace>.svc.cluster.local:<port>

# Example for demo database
redis-cli -h demo.redis-enterprise.svc.cluster.local -p 12000

# Test from a temporary pod
kubectl run redis-test --image=redis:latest -n redis-enterprise --rm -it -- bash
redis-cli -h demo -p 12000 PING
# Response: PONG
```

**Local Access (via port-forward):**
```bash
# Port-forward database service
kubectl port-forward -n redis-enterprise svc/demo 12000:12000

# Connect locally
redis-cli -h localhost -p 12000
```

### Creating Additional Databases

Create a file `my-database.yaml`:

```yaml
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseDatabase
metadata:
  name: my-app-db
  namespace: redis-enterprise
spec:
  redisEnterpriseCluster:
    name: redis-ent-eks
  memorySize: 1GB
  databasePort: 12001
  replication: true
  persistence: aofEveryOneSecond
  databaseServiceType: LoadBalancer
```

Apply it:
```bash
kubectl apply -f my-database.yaml
```

## 💾 Redis Flex (Auto Tiering) - Optional

Redis Flex (also called Auto Tiering) enables automatic tiering of data between RAM and flash storage (NVMe SSDs), allowing you to store more data at lower cost by extending Redis beyond RAM.

### What is Redis Flex?

- **Automatic Tiering**: Frequently accessed data stays in RAM, less-accessed data moves to flash
- **Cost Savings**: Flash storage is significantly cheaper than RAM
- **Transparent**: Applications use standard Redis commands - tiering is automatic
- **Performance**: Hot data in RAM maintains performance, warm/cold data on flash

### Requirements

**IMPORTANT**: Redis Flex requires **local NVMe SSDs** attached to EC2 instances. Standard EBS volumes (gp3, gp2, io1, etc.) **do NOT work**.

1. **EC2 Instance Types with Local NVMe SSDs**:
   - **i3 family**: i3.xlarge, i3.2xlarge, i3.4xlarge, i3.8xlarge
   - **i4i family**: i4i.xlarge, i4i.2xlarge, i4i.4xlarge, i4i.8xlarge (AWS Nitro)
   - **Storage**: Check instance specs for NVMe SSD capacity

2. **Local Storage Class**: Configure Kubernetes to use local NVMe devices

3. **Redis Enterprise 7.2.4+**: Redis Flex support built-in

### Configuration

To enable Redis Flex, update `terraform.tfvars`:

```hcl
#==============================================================================
# EC2 Instance Type with Local NVMe SSDs
#==============================================================================
node_instance_types = ["i3.xlarge"]  # Change from t3.xlarge to i3.xlarge

#==============================================================================
# Redis Flex Configuration
#==============================================================================
enable_redis_flex           = true         # Enable Redis Flex at cluster level
redis_flex_storage_class    = "local-scsi" # Storage class for NVMe devices
redis_flex_flash_disk_size  = "100G"       # Flash disk size per node
redis_flex_storage_driver   = "speedb"     # speedb (recommended) or rocksdb

# Enable for specific databases
sample_db_enable_redis_flex = true         # Enable for sample database
sample_db_rof_ram_size      = "10GB"       # RAM size (min 10% of total memory)
```

### Creating a Redis Flex Database

Create a database with Redis Flex enabled:

```yaml
apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseDatabase
metadata:
  name: my-flex-db
  namespace: redis-enterprise
spec:
  redisEnterpriseCluster:
    name: redis-ent-eks
  memorySize: 100GB        # Total memory (RAM + Flash)
  isRof: true              # Enable Redis Flex
  rofRamSize: 10GB         # RAM size (minimum 10% of memorySize)
  databasePort: 12002
  replication: true
  persistence: aofEverySecond
  databaseServiceType: ClusterIP
```

In this example:
- **Total capacity**: 100GB (10GB RAM + 90GB Flash)
- **Hot data**: Up to 10GB stays in RAM for fast access
- **Warm/cold data**: Up to 90GB automatically tiered to flash
- **Cost savings**: ~75% reduction vs 100GB all-RAM

### Setting Up Local NVMe Storage

Before enabling Redis Flex, you need to configure local storage on your EKS worker nodes:

1. **Create a local storage provisioner** (e.g., using [sig-storage-local-static-provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner))

2. **Create a StorageClass for local NVMe**:
   ```yaml
   apiVersion: storage.k8s.io/v1
   kind: StorageClass
   metadata:
     name: local-scsi
   provisioner: kubernetes.io/no-provisioner
   volumeBindingMode: WaitForFirstConsumer
   ```

3. **Discover and mount NVMe devices** on each worker node

### Verifying Redis Flex

```bash
# Check cluster has Redis Flex enabled
kubectl describe rec redis-ent-eks -n redis-enterprise | grep -A 5 redisOnFlashSpec

# Check database is using Redis Flex
kubectl get redb my-flex-db -n redis-enterprise -o yaml | grep -A 2 "isRof\|rofRamSize"

# Monitor memory/flash usage via Redis Enterprise UI
kubectl port-forward -n redis-enterprise svc/redis-ent-eks-ui 8443:8443
# Access: https://localhost:8443
```

### Important Notes

- **Cannot use EBS**: Redis Flex requires local NVMe SSDs, not network-attached storage
- **Instance costs**: i3/i4i instances are more expensive than t3 instances
- **Storage ephemeral**: Local NVMe data is lost if instance terminates (use replication + persistence)
- **No PVC expansion**: Cannot resize PVCs when Redis Flex is enabled
- **RAM minimum**: `rofRamSize` must be at least 10% of total `memorySize`

### Documentation

- [Redis Flex on Kubernetes](https://redis.io/docs/latest/operate/kubernetes/re-clusters/redis-flex/)
- [Redis on Flash Overview](https://redis.io/blog/redis-enterprise-flash/)
- [AWS EC2 Instance Types with NVMe](https://aws.amazon.com/ec2/instance-types/)

## 🚨 Troubleshooting

### Common Issues

1. **Operator pod not starting**
   ```bash
   kubectl describe pod -n redis-enterprise -l name=redis-enterprise-operator
   # Check events for errors
   ```

2. **Redis cluster pods stuck in Pending**
   ```bash
   kubectl describe pod -n redis-enterprise redis-ent-eks-0
   # Common issue: insufficient node resources or storage
   ```

3. **Storage issues**
   ```bash
   kubectl get pvc -n redis-enterprise
   kubectl get storageclass
   # Verify EBS CSI driver is running
   kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver
   ```

4. **Can't access services**
   ```bash
   kubectl get svc -n redis-enterprise
   # Verify services are ClusterIP type
   # Use kubectl port-forward for local access
   # For in-cluster access, use service FQDN: <svc>.<namespace>.svc.cluster.local
   ```

5. **Cluster not becoming ready**
   ```bash
   kubectl logs -n redis-enterprise redis-ent-eks-0 -c redis-enterprise-node
   # Check for licensing or configuration issues
   ```

### Getting Help

```bash
# Full cluster state
kubectl get all -n redis-enterprise

# Operator status
kubectl get deployment -n redis-enterprise redis-enterprise-operator

# Cluster validation
kubectl get rec redis-ent-eks -n redis-enterprise -o yaml

# Events
kubectl get events -n redis-enterprise --sort-by='.lastTimestamp'
```

## 🌐 External Access (Optional)

By default, services use ClusterIP for internal-only access (per Redis Enterprise K8s docs). For external access, this project provides **automated Terraform modules** following official Redis Enterprise documentation.

**See [EXTERNAL-ACCESS.md](EXTERNAL-ACCESS.md) for complete documentation.**

### Quick Start: Enable External Access

Choose one of three options:

#### Option 1: NGINX Ingress (Recommended for Production)

**Best for:** Multiple databases, production deployments, cost optimization

```hcl
# In terraform.tfvars
external_access_type = "nginx-ingress"
expose_redis_ui        = true
expose_redis_databases = true
ingress_domain         = "redis.example.com"
enable_tls             = false  # Start with testing mode
```

**What you get:**
- ✅ Single AWS NLB (~$16/month total)
- ✅ NGINX Ingress Controller (automated deployment)
- ✅ TLS mode (production) or non-TLS mode (testing)
- ✅ SNI-based routing for multiple databases
- ✅ Follows [Redis Enterprise official documentation](https://redis.io/docs/latest/operate/kubernetes/networking/ingress/)

**Cost:** ~$16/month (single NLB for all services)

#### Option 2: NLB (Simple Layer 4 Load Balancing)

**Best for:** Simple deployments, getting started quickly

```hcl
# In terraform.tfvars
external_access_type = "nlb"
expose_redis_ui        = true
expose_redis_databases = true
```

**What you get:**
- ✅ AWS Network Load Balancer per service
- ✅ Simple setup, no additional configuration
- ✅ Low latency (Layer 4)

**Cost:** ~$16/month per service (UI + each database)

#### Option 3: Internal Only (Default)

```hcl
# In terraform.tfvars
external_access_type = "none"
```

Access via `kubectl port-forward` or from within the cluster only.

### Deployment

```bash
# Update terraform.tfvars with your choice above, then:
terraform apply

# Get access details
terraform output
```

### Access Examples

**After deployment with NGINX Ingress (non-TLS mode):**
```bash
# Get NLB DNS
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Connect to database
redis-cli -h $NLB_DNS -p 12000 -a admin
```

**With TLS mode enabled:**
```bash
# Requires DNS configuration first (see EXTERNAL-ACCESS.md)
redis-cli -h demo-redis.example.com -p 443 -a admin \
  --tls \
  --sni demo-redis.example.com
```

See **[EXTERNAL-ACCESS.md](EXTERNAL-ACCESS.md)** for:
- Complete configuration guide
- Architecture diagrams
- TLS setup instructions
- Client connection examples (Python, Node.js, redis-cli)
- Troubleshooting
- Cost comparisons

## 🔒 Security Notes

### Production Recommendations

1. **Network Security**
   - Use private subnets for worker nodes (enable NAT gateway)
   - Restrict security group rules to specific IP ranges
   - Implement Kubernetes network policies

2. **Secrets Management**
   - Use AWS Secrets Manager or Systems Manager Parameter Store
   - Enable encryption at rest for secrets
   - Rotate credentials regularly

3. **Access Control**
   - Enable EKS cluster endpoint private access only
   - Use IAM roles for service accounts (IRSA)
   - Implement RBAC policies

4. **Monitoring & Logging**
   - Enable EKS control plane logging
   - Deploy Prometheus/Grafana for metrics
   - Configure CloudWatch alarms
   - Set up audit logging

5. **TLS/SSL**
   - Enable TLS for Redis databases
   - Use valid SSL certificates (not self-signed)
   - Configure TLS for cluster communication

## 📈 Scaling

### Horizontal Scaling

```bash
# Scale EKS node group
aws eks update-nodegroup-config \
  --cluster-name your-prefix-redis-ent-eks \
  --nodegroup-name your-prefix-redis-ent-eks-node-group \
  --scaling-config desiredSize=5

# Scale Redis Enterprise cluster (edit REC)
kubectl edit rec redis-ent-eks -n redis-enterprise
# Change spec.nodes to desired count
```

### Vertical Scaling

Update `terraform.tfvars`:
```hcl
node_instance_types = ["r6i.xlarge"]  # Change instance type
redis_cluster_memory = "8Gi"          # Increase memory
```

Then apply:
```bash
terraform apply
```

## 💰 Cost Optimization

### Development/Testing
- Use t3.xlarge instances
- 3 nodes minimum
- gp3 storage (most cost-effective)
- Destroy when not in use: `terraform destroy`

### Production
- Use reserved instances or Savings Plans
- Consider r6i instances (memory-optimized)
- Enable cluster autoscaling
- Monitor and rightsize resources

## 📝 Module Structure

```
.
├── main.tf                      # Main orchestration
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values
├── provider.tf                  # Provider configuration
├── versions.tf                  # Provider versions
├── terraform.tfvars.example     # Configuration template
├── README.md                    # This file
└── modules/
    ├── vpc/                     # VPC and networking
    ├── eks_cluster/             # EKS control plane
    ├── eks_node_group/          # EKS worker nodes
    ├── ebs_csi_driver/          # EBS CSI driver and storage class
    ├── redis_operator/          # Redis Enterprise operator (Helm)
    ├── redis_cluster/           # Redis Enterprise cluster (REC)
    └── redis_database/          # Redis database (REDB)
```

## 🔗 Additional Resources

- [Redis Enterprise on Kubernetes Documentation](https://redis.io/docs/latest/operate/kubernetes/)
- [Supported Kubernetes Distributions](https://redis.io/docs/latest/operate/kubernetes/reference/supported_k8s_distributions/)
- [Redis Enterprise Kubernetes Architecture](https://redis.io/docs/latest/operate/kubernetes/architecture/)
- [EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Redis Enterprise Operator GitHub](https://github.com/RedisLabs/redis-enterprise-k8s-docs)

---

**⚠️ Important**: This creates real AWS resources that incur costs (~$400-500/month for dev/test). Remember to run `terraform destroy` when done testing.
