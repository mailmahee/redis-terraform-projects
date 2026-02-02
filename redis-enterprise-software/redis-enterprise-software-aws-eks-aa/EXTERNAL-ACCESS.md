# External Access to Redis Enterprise on EKS

This guide explains how to enable external access to your Redis Enterprise cluster and databases running on Amazon EKS.

## Overview

The project supports multiple external access methods via the `external_access` module:

- **NLB (Network Load Balancer)** - ✅ Available (Simple Layer 4 load balancing)
- **NGINX Ingress** - ✅ Available (Following Redis Enterprise official documentation)
- **None (Internal Only)** - Default

## Quick Start: Enable NLB External Access

### 1. Update terraform.tfvars

```hcl
# Enable external access via NLB
external_access_type = "nlb"

# Choose what to expose
expose_redis_ui        = true   # Expose Redis Enterprise UI
expose_redis_databases = true   # Expose Redis databases
```

### 2. Apply Changes

```bash
terraform apply
```

**What gets created:**
- AWS Network Load Balancer for Redis Enterprise UI (port 8443)
- AWS Network Load Balancer for each exposed database (e.g., port 12000)

**Cost:** ~$16/month per NLB

### 3. Get LoadBalancer DNS Names

```bash
# UI LoadBalancer
terraform output

# Or check Kubernetes services
kubectl get svc -n redis-enterprise | grep external
```

### 4. Access Externally

**Redis Enterprise UI:**
```bash
# Get the DNS name
UI_DNS=$(kubectl get svc -n redis-enterprise -o jsonpath='{.items[?(@.metadata.name=="redis-ent-eks-ui-external")].status.loadBalancer.ingress[0].hostname}')

# Open in browser
open https://$UI_DNS:8443

# Login:
# Username: admin@admin.com
# Password: (your configured password)
```

**Redis Database:**
```bash
# Get the DNS name
DB_DNS=$(kubectl get svc -n redis-enterprise -o jsonpath='{.items[?(@.metadata.name=="demo-external")].status.loadBalancer.ingress[0].hostname}')

# Connect with redis-cli
redis-cli -h $DB_DNS -p 12000 -a admin

# Test
PING
SET key1 "value1"
GET key1
```

## Configuration Options

### External Access Types

| Type | Description | Status | Cost |
|------|-------------|--------|------|
| `none` | Internal access only (ClusterIP) | ✅ Default | Free |
| `nlb` | AWS Network Load Balancer | ✅ Available | ~$16/month per service |
| `nginx-ingress` | NGINX Ingress Controller | ✅ Available | ~$16/month total |

### NLB Mode (Current)

**Advantages:**
- ✅ Simple, production-ready
- ✅ Low latency (Layer 4)
- ✅ Preserves source IP
- ✅ No additional setup

**Disadvantages:**
- ❌ One NLB per service (can get expensive with many databases)
- ❌ No domain-based routing
- ❌ No built-in TLS termination

### NGINX Ingress Mode (Available)

**Implementation:** Follows [Redis Enterprise official documentation](https://redis.io/docs/latest/operate/kubernetes/networking/ingress/)

**Advantages:**
- ✅ Single NLB for all services (cost-effective at scale)
- ✅ Custom domain support with hostname-based routing
- ✅ TLS passthrough (production mode)
- ✅ Non-TLS mode for testing
- ✅ SNI support for multiple databases
- ✅ Production-ready architecture

**Disadvantages:**
- ❌ Requires DNS configuration (TLS mode)
- ❌ Slightly more complex setup
- ❌ TLS mode requires TLS enabled on Redis databases

## Quick Start: Enable NGINX Ingress External Access

### Option A: Non-TLS Mode (Testing)

**Best for:** Initial testing without TLS complexity

#### 1. Update terraform.tfvars

```hcl
# Enable external access via NGINX Ingress
external_access_type = "nginx-ingress"

# Choose what to expose
expose_redis_ui        = true
expose_redis_databases = true

# NGINX configuration
ingress_domain       = "redis.example.com"  # Your domain
nginx_instance_count = 2                    # HA replicas
enable_tls           = false                # Testing mode (no TLS)
```

#### 2. Apply Changes

```bash
terraform apply
```

**What gets created:**
- NGINX Ingress Controller with AWS NLB (single NLB for everything)
- TCP port forwarding for direct database access
- HTTP ingress for UI

**Cost:** ~$16/month (single NLB)

#### 3. Get LoadBalancer DNS Name

```bash
# Get the NLB DNS name
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Example output:
# NAME                       TYPE           EXTERNAL-IP
# ingress-nginx-controller   LoadBalancer   abc123-xyz.elb.us-west-2.amazonaws.com
```

#### 4. Access Externally (Non-TLS Mode)

**Redis Enterprise UI:**
```bash
# Get the NLB DNS
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Access via your domain (requires DNS CNAME: ui-redis.example.com → NLB_DNS)
open http://ui-redis.example.com
```

**Redis Database:**
```bash
# Connect directly to NLB on database port
redis-cli -h $NLB_DNS -p 12000 -a admin

# Test
PING
SET key1 "value1"
GET key1
```

### Option B: TLS Mode (Production)

**Best for:** Production deployments with TLS security

**Requirements:**
- TLS must be enabled on Redis databases
- DNS records must be configured
- Clients must support SNI

#### 1. Enable TLS on Redis Databases

First, ensure your databases have TLS enabled. Update the `redis_database` module configuration:

```hcl
# In your main.tf or database configuration
sample_db_tls_mode = "enabled"
```

#### 2. Update terraform.tfvars

```hcl
# Enable external access via NGINX Ingress with TLS
external_access_type = "nginx-ingress"

# Choose what to expose
expose_redis_ui        = true
expose_redis_databases = true

# NGINX configuration
ingress_domain       = "redis.example.com"  # Your domain
nginx_instance_count = 2                    # HA replicas
enable_tls           = true                 # Production mode (TLS)
```

#### 3. Apply Changes

```bash
terraform apply
```

**What gets created:**
- NGINX Ingress Controller with SSL passthrough enabled
- Ingress resources with TLS configuration
- Services with port 443 and "redis" port name
- SNI-based hostname routing

#### 4. Configure DNS Records

Create CNAME records pointing to the NLB:

```bash
# Get the NLB DNS name
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Create these DNS records in your DNS provider:
# ui-redis.example.com     → CNAME → $NLB_DNS
# demo-redis.example.com   → CNAME → $NLB_DNS
```

#### 5. Access Externally (TLS Mode)

**Redis Enterprise UI:**
```bash
# Access via HTTPS on port 443
open https://ui-redis.example.com:443

# Login:
# Username: admin@admin.com
# Password: (your configured password)
```

**Redis Database:**
```bash
# Connect with TLS using SNI hostname
redis-cli -h demo-redis.example.com -p 443 -a admin \
  --tls \
  --sni demo-redis.example.com

# Test
PING
SET key1 "value1"
GET key1
```

**Python example:**
```python
import redis

# Connect with TLS and SNI
r = redis.Redis(
    host='demo-redis.example.com',
    port=443,
    password='admin',
    ssl=True,
    ssl_cert_reqs='required',
    ssl_sni='demo-redis.example.com'
)

# Test connection
r.ping()
r.set('key1', 'value1')
print(r.get('key1'))
```

## Architecture

### NLB Architecture

```
Internet
    ↓
AWS NLB (UI)       AWS NLB (demo DB)
    ↓                      ↓
redis-ent-eks-ui-external  demo-external (K8s Service)
    ↓                      ↓
redis-ent-eks-ui-0         demo pod
    (Redis Enterprise UI)  (Redis Database)
```

### NGINX Ingress Architecture (TLS Mode - Production)

```
Internet
    ↓
DNS (ui-redis.example.com, demo-redis.example.com)
    ↓
AWS NLB (single, port 443)
    ↓
NGINX Ingress Controller (SSL passthrough enabled)
    ↓
   ├─→ Ingress (UI, TLS) → redis-ent-eks-ui:8443
   │   Host: ui-redis.example.com
   │   Port: 443 (external) → 8443 (internal)
   │   SSL Passthrough: true
   │
   └─→ Ingress (DB, TLS) → demo-external service
       Host: demo-redis.example.com
       Port: 443 (external) → 12000 (internal)
       SSL Passthrough: true
       SNI: demo-redis.example.com
```

### NGINX Ingress Architecture (Non-TLS Mode - Testing)

```
Internet
    ↓
AWS NLB (single, multiple ports)
    ↓
NGINX Ingress Controller (TCP stream mode)
    ↓
   ├─→ Port 8443 → redis-ent-eks-ui:8443 (UI)
   └─→ Port 12000 → demo:12000 (Database)
```

## Security Considerations

### 1. TLS Encryption

**For UI:**
- Redis Enterprise UI uses self-signed certificate by default
- For production, configure custom TLS certificates

**For Databases:**
```hcl
# Enable TLS for databases
sample_db_tls_mode = "enabled"
```

### 2. Network Security

**Restrict NLB access by source IP** (future enhancement):
```hcl
# Example (not yet implemented)
nlb_allowed_cidrs = ["YOUR.IP.ADDRESS/32"]
```

**Security Groups:**
- NLBs automatically configure security groups
- EKS security groups allow traffic from NLB

### 3. Authentication

**Always use strong passwords:**
```hcl
redis_cluster_password = "VeryStrongPassword123!"
sample_db_password = "DatabasePassword456!"
```

## Switching Between Modes

### From Internal (none) → NLB

```hcl
# terraform.tfvars
external_access_type = "nlb"
expose_redis_ui = true
expose_redis_databases = true
```

```bash
terraform apply
# Creates: 2 NLBs
# Changes: 0 to existing infrastructure
```

### From NLB → Internal (none)

```hcl
# terraform.tfvars
external_access_type = "none"
```

```bash
terraform apply
# Destroys: NLB services
# Changes: 0 to Redis infrastructure
```

### From NLB → NGINX Ingress (Non-TLS)

```hcl
# terraform.tfvars
external_access_type = "nginx-ingress"
ingress_domain = "redis.example.com"
enable_tls = false  # Testing mode
```

```bash
terraform apply
# Destroys: Old NLBs (UI + databases)
# Creates: NGINX Ingress Controller + 1 NLB with TCP port forwarding
```

### From NGINX Non-TLS → NGINX TLS Mode

```hcl
# terraform.tfvars
external_access_type = "nginx-ingress"
ingress_domain = "redis.example.com"
enable_tls = true  # Production mode

# IMPORTANT: Also enable TLS on databases
sample_db_tls_mode = "enabled"
```

```bash
terraform apply
# Changes: Updates NGINX configuration
# Creates: Ingress resources with SSL passthrough
# Requires: DNS records (see documentation above)
```

## Troubleshooting

### NLB Not Creating

**Check service status:**
```bash
kubectl get svc -n redis-enterprise
kubectl describe svc redis-ent-eks-ui-external -n redis-enterprise
```

**Common issues:**
- AWS Load Balancer Controller not installed (not required for NLB)
- Insufficient permissions (check EKS node IAM role)

### Cannot Connect to NLB

**Verify LoadBalancer is ready:**
```bash
kubectl get svc -n redis-enterprise -o wide
# Check EXTERNAL-IP column - should show DNS name, not <pending>
```

**Test DNS resolution:**
```bash
nslookup <loadbalancer-dns-name>
```

**Check security groups:**
```bash
# Ensure your IP can reach the NLB
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/bamos-redis-ent-eks,Values=owned"
```

### High Costs

**With many databases using NLB mode:**
- Each database gets its own NLB (~$16/month each)
- **Solution:** Switch to NGINX Ingress mode (~$16/month total for all services)

### NGINX Ingress Not Installing

**Check Helm release status:**
```bash
helm list -n ingress-nginx
kubectl get pods -n ingress-nginx
kubectl describe pod <nginx-pod-name> -n ingress-nginx
```

**Common issues:**
- Helm not installed or configured
- Insufficient cluster resources
- Version compatibility issues

**Fix:**
```bash
# Manually install if needed
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace
```

### Cannot Connect via NGINX Ingress (TLS Mode)

**Verify Ingress resources:**
```bash
kubectl get ingress -n redis-enterprise
kubectl describe ingress <ingress-name> -n redis-enterprise
```

**Check DNS resolution:**
```bash
nslookup demo-redis.example.com
# Should resolve to NLB DNS name
```

**Verify TLS is enabled on database:**
```bash
kubectl get redb -n redis-enterprise -o yaml | grep tlsMode
# Should show: tlsMode: enabled
```

**Test with curl (debugging):**
```bash
# Test if NLB is responding on port 443
curl -v -k https://demo-redis.example.com:443
```

**Common issues:**
- DNS not configured (TLS mode requires DNS)
- TLS not enabled on Redis database
- SNI not provided by client
- Wrong hostname/port in client connection

### Cannot Connect via NGINX Ingress (Non-TLS Mode)

**Verify TCP port forwarding:**
```bash
# Check if ports are exposed on NLB
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Check ConfigMap
kubectl get cm tcp-services -n ingress-nginx -o yaml
```

**Test connectivity:**
```bash
# Get NLB DNS
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test with redis-cli
redis-cli -h $NLB_DNS -p 12000 PING
```

**Common issues:**
- TCP ConfigMap not loaded by NGINX controller
- Ports not exposed on NLB service
- Database service not found

## Cost Comparison

### Scenario: 1 UI + 5 Databases

| Mode | NLBs | Monthly Cost | Notes |
|------|------|--------------|-------|
| Internal (none) | 0 | $0 | Internal access only |
| NLB | 6 | ~$96 | 6 NLBs × $16/month |
| NGINX Ingress (future) | 1 | ~$16 | Single NLB for all |

## Module Structure

```
modules/external_access/
├── main.tf              # Conditional orchestrator
├── variables.tf
├── outputs.tf
├── versions.tf
├── nlb/                 # ✅ Simple NLB mode
│   ├── main.tf          # Kubernetes LoadBalancer services
│   ├── variables.tf
│   ├── outputs.tf
│   └── versions.tf
└── nginx_ingress/       # ✅ NGINX Ingress mode
    ├── main.tf          # Helm + Ingress resources (TLS & non-TLS)
    ├── variables.tf     # Includes enable_tls configuration
    └── outputs.tf       # LoadBalancer DNS, URLs, DNS records
```

## TLS Configuration for NGINX Ingress

### Enabling TLS on Redis Databases

For NGINX Ingress TLS mode, databases **must** have TLS enabled. Add this to your database configuration:

```hcl
# In modules/redis_database or your database configuration
tls_mode = "enabled"
```

Or via terraform.tfvars:
```hcl
sample_db_tls_mode = "enabled"
```

### Client Connection Requirements (TLS Mode)

**redis-cli:**
```bash
redis-cli -h demo-redis.example.com -p 443 -a admin \
  --tls \
  --sni demo-redis.example.com
```

**Python:**
```python
import redis

r = redis.Redis(
    host='demo-redis.example.com',
    port=443,
    password='admin',
    ssl=True,
    ssl_cert_reqs='required',
    ssl_sni='demo-redis.example.com'  # SNI is required!
)
```

**Node.js:**
```javascript
const redis = require('redis');

const client = redis.createClient({
    socket: {
        host: 'demo-redis.example.com',
        port: 443,
        tls: true,
        servername: 'demo-redis.example.com'  // SNI
    },
    password: 'admin'
});
```

### DNS Configuration

After deploying NGINX Ingress in TLS mode, configure DNS:

```bash
# Get Terraform outputs
terraform output

# Or get NLB DNS directly
kubectl get svc ingress-nginx-controller -n ingress-nginx

# Create CNAME records:
# ui-redis.example.com     → CNAME → abc123-xyz.elb.us-west-2.amazonaws.com
# demo-redis.example.com   → CNAME → abc123-xyz.elb.us-west-2.amazonaws.com
```

## Implemented Features

- ✅ NLB mode (simple Layer 4 load balancing)
- ✅ NGINX Ingress Controller module
- ✅ Custom domain support with SNI
- ✅ TLS mode with SSL passthrough
- ✅ Non-TLS mode for testing
- ✅ Hostname-based routing for multiple databases

## Future Enhancements

- [ ] HAProxy Ingress support
- [ ] Istio Gateway/VirtualService support
- [ ] Automatic TLS certificate management (cert-manager)
- [ ] Source IP restrictions via NLB/Ingress annotations
- [ ] Custom health check configuration
- [ ] Rate limiting and WAF integration

## References

- [AWS Network Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/network/)
- [Kubernetes LoadBalancer Service](https://kubernetes.io/docs/concepts/services-networking/service/#loadbalancer)
- [Redis Enterprise on Kubernetes](https://redis.io/docs/latest/operate/kubernetes/)
