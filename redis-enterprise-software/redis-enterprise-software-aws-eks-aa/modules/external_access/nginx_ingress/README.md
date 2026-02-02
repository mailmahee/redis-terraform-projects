# NGINX Ingress External Access Module

This module implements external access to Redis Enterprise on Kubernetes using **NGINX Ingress Controller**, following the [official Redis Enterprise documentation](https://redis.io/docs/latest/operate/kubernetes/networking/ingress/).

## Features

### ✅ Two Operating Modes

**1. TLS Mode (Production)**
- SSL passthrough for encrypted traffic
- Port 443 for external access (standard HTTPS port)
- SNI-based hostname routing for multiple databases
- Requires TLS enabled on Redis databases
- Requires DNS configuration
- Production-ready security

**2. Non-TLS Mode (Testing)**
- Direct TCP port forwarding
- No TLS requirements
- Uses database ports directly (e.g., 12000)
- No DNS configuration needed
- Simpler for initial testing

### ✅ Cost Effective

- **Single AWS NLB** for all services (UI + all databases)
- **~$16/month total** vs ~$16/month per service with standalone NLBs
- Ideal for deployments with multiple databases

### ✅ Production Ready

- High availability with multiple NGINX replicas
- Automatic failover
- Follows Redis Enterprise best practices
- SSL passthrough preserves end-to-end encryption

## Architecture

### TLS Mode (Production)

```
Internet
    ↓
DNS (CNAME records)
    ↓
AWS NLB (port 443)
    ↓
NGINX Ingress Controller
  - SSL Passthrough: Enabled
  - SNI Routing: Enabled
    ↓
    ├─→ ui-redis.example.com → redis-ent-eks-ui:8443
    └─→ demo-redis.example.com → demo-external:443 → demo:12000
```

### Non-TLS Mode (Testing)

```
Internet
    ↓
AWS NLB (multiple ports: 8443, 12000, etc.)
    ↓
NGINX Ingress Controller
  - TCP Stream: Enabled
  - Direct Port Forwarding
    ↓
    ├─→ Port 8443 → redis-ent-eks-ui:8443
    └─→ Port 12000 → demo:12000
```

## Usage

### Basic Configuration

```hcl
module "nginx_ingress_access" {
  source = "./modules/external_access/nginx_ingress"

  namespace = "redis-enterprise"

  # Redis Enterprise UI
  redis_ui_service_name = "redis-ent-eks-ui"
  expose_ui             = true

  # Redis Enterprise Databases
  redis_db_services = {
    "demo" = {
      port         = 12000
      service_name = "demo"
    }
  }
  expose_databases = true

  # NGINX Configuration
  ingress_domain       = "redis.example.com"
  nginx_instance_count = 2
  enable_tls           = false  # Start with testing mode

  tags = {
    Environment = "production"
  }
}
```

### TLS Mode Configuration

```hcl
module "nginx_ingress_access" {
  source = "./modules/external_access/nginx_ingress"

  # ... same as above ...

  enable_tls = true  # Enable TLS mode

  # NOTE: Requires TLS enabled on Redis databases
  # NOTE: Requires DNS configuration (see below)
}
```

## Requirements

### For All Modes

- Kubernetes cluster (EKS, GKE, AKS, etc.)
- Helm provider configured
- Kubectl access configured

### For TLS Mode Only

1. **TLS must be enabled on Redis databases:**
   ```hcl
   # In your database configuration
   tls_mode = "enabled"
   ```

2. **DNS records must be created:**
   - Point hostnames to NGINX LoadBalancer DNS
   - Example: `demo-redis.example.com` → CNAME → `abc123-xyz.elb.us-west-2.amazonaws.com`

3. **Clients must support SNI:**
   - Most modern clients support this (redis-cli, Python redis, Node.js ioredis, etc.)

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `namespace` | Kubernetes namespace for Redis Enterprise | `string` | n/a | yes |
| `redis_ui_service_name` | Redis Enterprise UI service name | `string` | n/a | yes |
| `expose_ui` | Expose Redis Enterprise UI externally | `bool` | `false` | no |
| `redis_db_services` | Map of databases to expose | `map(object)` | `{}` | no |
| `expose_databases` | Expose Redis databases externally | `bool` | `false` | no |
| `ingress_domain` | Base domain for ingress (e.g., redis.example.com) | `string` | `""` | yes* |
| `nginx_instance_count` | Number of NGINX replicas | `number` | `2` | no |
| `enable_tls` | Enable TLS mode (production) | `bool` | `false` | no |
| `tags` | Tags to apply to resources | `map(string)` | `{}` | no |

\* Required when using this module

## Outputs

| Name | Description |
|------|-------------|
| `ingress_loadbalancer_dns` | AWS NLB DNS name for NGINX Ingress |
| `ui_url_tls` | Redis Enterprise UI URL (TLS mode) |
| `ui_url_non_tls` | Redis Enterprise UI URL (non-TLS mode) |
| `database_urls_tls` | Database connection URLs (TLS mode) |
| `database_urls_non_tls` | Database connection URLs (non-TLS mode) |
| `mode` | Current mode (TLS or non-TLS) |
| `dns_records_required` | DNS records to create (TLS mode) |

## Testing

### 1. Deploy in Non-TLS Mode

```hcl
enable_tls = false
```

```bash
terraform apply
```

### 2. Get NLB DNS

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

### 3. Test Connection

**UI Access:**
```bash
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$NLB_DNS:8443
```

**Database Access:**
```bash
redis-cli -h $NLB_DNS -p 12000 -a admin PING
```

### 4. Upgrade to TLS Mode

1. Enable TLS on databases
2. Configure DNS records
3. Update configuration:
   ```hcl
   enable_tls = true
   ```
4. Apply changes:
   ```bash
   terraform apply
   ```

## Connection Examples

### redis-cli (TLS Mode)

```bash
redis-cli -h demo-redis.example.com -p 443 -a admin \
  --tls \
  --sni demo-redis.example.com
```

### Python (TLS Mode)

```python
import redis

r = redis.Redis(
    host='demo-redis.example.com',
    port=443,
    password='admin',
    ssl=True,
    ssl_cert_reqs='required',
    ssl_sni='demo-redis.example.com'
)

r.ping()
```

### Node.js (TLS Mode)

```javascript
const redis = require('redis');

const client = redis.createClient({
    socket: {
        host: 'demo-redis.example.com',
        port: 443,
        tls: true,
        servername: 'demo-redis.example.com'
    },
    password: 'admin'
});

await client.connect();
await client.ping();
```

## Troubleshooting

### NGINX Controller Not Deploying

```bash
# Check Helm release
helm list -n ingress-nginx

# Check pods
kubectl get pods -n ingress-nginx

# View logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### TLS Mode: Cannot Connect

**Check DNS:**
```bash
nslookup demo-redis.example.com
# Should resolve to NLB DNS
```

**Check Ingress:**
```bash
kubectl get ingress -n redis-enterprise
kubectl describe ingress demo-ingress -n redis-enterprise
```

**Verify TLS on database:**
```bash
kubectl get redb demo -n redis-enterprise -o yaml | grep tlsMode
# Should show: tlsMode: enabled
```

### Non-TLS Mode: Cannot Connect

**Check ConfigMap:**
```bash
kubectl get cm tcp-services -n ingress-nginx -o yaml
```

**Check NLB ports:**
```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Should show ports 8443, 12000, etc.
```

## References

- [Redis Enterprise Ingress Documentation](https://redis.io/docs/latest/operate/kubernetes/networking/ingress/)
- [NGINX Ingress Controller](https://kubernetes.github.io/ingress-nginx/)
- [Redis Enterprise on Kubernetes](https://redis.io/docs/latest/operate/kubernetes/)

## Implementation Details

### What Gets Created

**All Modes:**
- Helm release for NGINX Ingress Controller
- AWS Network Load Balancer (via Kubernetes LoadBalancer service)
- NGINX deployment with 2+ replicas (configurable)

**TLS Mode:**
- Kubernetes Ingress resources with SSL passthrough annotations
- ClusterIP services with port 443 and "redis" port name
- TLS blocks for SNI routing

**Non-TLS Mode:**
- TCP ConfigMap for port forwarding
- Patched NGINX controller deployment (TCP services config)
- Patched NLB service (exposed database ports)

### Service Port Configuration (TLS Mode)

Per [Redis documentation requirements](https://redis.io/docs/latest/operate/kubernetes/networking/ingress/#requirements):

- **External port:** 443 (standard TLS port)
- **Port name:** "redis" (required for Redis)
- **Target port:** Actual database port (e.g., 12000)
- **Service type:** ClusterIP (routing via Ingress)

Example:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-external
spec:
  type: ClusterIP
  ports:
  - name: redis        # Required port name
    port: 443          # External port
    targetPort: 12000  # Internal database port
```

### Annotations (TLS Mode)

Per Redis documentation:

```yaml
nginx.ingress.kubernetes.io/ssl-passthrough: "true"
nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
```

These ensure:
- TLS traffic passes through NGINX without termination
- End-to-end encryption is preserved
- Redis handles TLS directly
