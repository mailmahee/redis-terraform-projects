# Testing External Access to Redis Enterprise

This guide provides step-by-step instructions for testing external access to Redis Enterprise databases via NGINX Ingress and AWS Network Load Balancer (NLB).

## Prerequisites

- Terraform deployment completed successfully
- NGINX Ingress with non-TLS mode enabled (`external_access_type = "nginx-ingress"`, `enable_tls = false`)
- Sample database created (`create_sample_database = true`)
- Bastion instance created (`create_bastion = true`)

**Bastion IAM Credentials:**
- The bastion instance is automatically configured with an IAM instance profile
- kubectl is automatically configured during instance launch
- You can run kubectl commands directly from the bastion (no manual AWS credential setup needed)
- You can also run kubectl commands from your local machine if preferred

## Testing Workflow

### Step 1: Get Connection Information

You can run kubectl commands from either:
- **Your local machine** (if kubectl is configured locally)
- **The bastion instance** (kubectl is auto-configured via IAM instance profile)

**Option A: From your local machine:**
```bash
# Get bastion SSH command
terraform output -raw bastion_ssh_command

# Get NLB DNS name
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get database password
kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d

# Get database port (should be 12000 by default)
kubectl get redb demo -n redis-enterprise -o jsonpath='{.spec.port}'
```

**Option B: From the bastion instance:**
```bash
# SSH to bastion
ssh -i ~/.ssh/your-key.pem ubuntu@<bastion-ip>

# Once on bastion, kubectl is already configured - run commands directly:
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d
kubectl get redb demo -n redis-enterprise -o jsonpath='{.spec.port}'
```

**Example output:**
```
Bastion SSH: ssh -i ~/.ssh/your-key.pem ubuntu@ec2-54-XXX-XXX-XXX.us-west-2.compute.amazonaws.com
NLB DNS: a56a40e690e8b4ea18ed75fa2a926fc3-5f2bb8452d3aade0.elb.us-west-2.amazonaws.com
Password: admin
Port: 12000
```

### Step 2: Verify Port is Exposed on NLB

Check which ports are currently exposed on the NLB service:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[*].port}'
```

**Expected output:** Should include your database port (e.g., `80 443 12000`)

**If your database port is missing:**

This indicates the terraform provisioner didn't execute correctly (known bug). Manually expose the port:

```bash
# Replace 12000 with your database port
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/ports/-", "value": {"name": "redis-12000", "port": 12000, "protocol": "TCP", "targetPort": 12000}}]'
```

**Verify the port was added:**

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[*].port}'
```

### Step 3: Verify TCP ConfigMap Configuration

Check that the database is mapped in the TCP services ConfigMap:

```bash
kubectl get configmap tcp-services -n ingress-nginx -o yaml
```

**Expected output:**
```yaml
data:
  "12000": "redis-enterprise/demo:12000"
```

**If missing, add it manually:**

```bash
kubectl patch configmap tcp-services -n ingress-nginx \
  --type merge \
  -p '{"data":{"12000":"redis-enterprise/demo:12000"}}'
```

### Step 4: Wait for NLB Propagation

**CRITICAL: AWS NLB takes approximately 30 seconds to propagate new port configurations.**

After exposing a port, you must wait before testing connectivity:

```bash
echo "Waiting 30 seconds for NLB propagation..."
sleep 30
```

**Why this matters:**
- NLB needs to register the new target port across all availability zones
- Testing immediately will result in connection timeouts
- This delay is **normal AWS behavior**, not a bug

### Step 5: Test Connectivity from Bastion

Now connect to the bastion and test Redis connectivity:

```bash
# SSH to bastion (use the command from Step 1)
ssh -i ~/.ssh/your-key.pem ubuntu@ec2-54-XXX-XXX-XXX.us-west-2.compute.amazonaws.com

# Test connectivity (replace with your NLB DNS and password)
redis-cli -h <NLB-DNS> -p 12000 -a <password> --no-auth-warning PING
```

**Expected output:** `PONG`

**Example:**
```bash
redis-cli -h a56a40e690e8b4ea18ed75fa2a926fc3-5f2bb8452d3aade0.elb.us-west-2.amazonaws.com \
  -p 12000 \
  -a admin \
  --no-auth-warning PING
```

**Output:** `PONG`

### Step 6: Run Additional Tests

Once connectivity is confirmed, test basic Redis operations:

```bash
# Set a key
redis-cli -h <NLB-DNS> -p 12000 -a <password> --no-auth-warning SET test "hello from bastion"

# Get the key
redis-cli -h <NLB-DNS> -p 12000 -a <password> --no-auth-warning GET test

# Check database info
redis-cli -h <NLB-DNS> -p 12000 -a <password> --no-auth-warning INFO server

# Test from inside cluster (for comparison)
kubectl run redis-test --image=redis:latest -n redis-enterprise --rm -i --restart=Never -- \
  redis-cli -h demo -p 12000 -a <password> PING
```

## Testing Manually Created Databases

If you create additional databases via kubectl (not terraform), follow these steps to enable external access:

### 1. Create your database

```bash
kubectl apply -f my-database.yaml -n redis-enterprise
```

### 2. Wait for database to be ready

```bash
kubectl wait --for=condition=ready redb/my-db -n redis-enterprise --timeout=300s
```

### 3. Get database port

```bash
kubectl get redb my-db -n redis-enterprise -o jsonpath='{.spec.port}'
# Example output: 15000
```

### 4. Update TCP ConfigMap

```bash
# Replace 15000 with your database port, my-db with your database service name
kubectl patch configmap tcp-services -n ingress-nginx \
  --type merge \
  -p '{"data":{"15000":"redis-enterprise/my-db:15000"}}'
```

### 5. Expose port on NLB

```bash
# Replace 15000 with your database port
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/ports/-", "value": {"name": "redis-15000", "port": 15000, "protocol": "TCP", "targetPort": 15000}}]'
```

### 6. Wait for NLB propagation

```bash
sleep 30
```

### 7. Test connectivity

```bash
# Get database password
kubectl get secret my-db-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d

# Get NLB DNS
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test from bastion
redis-cli -h <NLB-DNS> -p 15000 -a <password> --no-auth-warning PING
```

## Troubleshooting

### Connection Timeout

**Symptoms:** `Could not connect to Redis at <NLB-DNS>:12000: Connection timed out`

**Causes:**
1. **NLB propagation delay** - Wait 30 seconds after exposing ports
2. **Port not exposed** - Verify port is in NLB service spec (Step 2)
3. **ConfigMap not updated** - Verify TCP ConfigMap has correct mapping (Step 3)
4. **Security groups** - Check NLB security group allows inbound traffic on database port

**Solution:**
```bash
# Check all ports on NLB service
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[*].port}'

# Check ConfigMap
kubectl get configmap tcp-services -n ingress-nginx -o yaml

# If missing, follow Steps 2-4 again
```

### Authentication Errors

**Symptoms:** `NOAUTH Authentication required`

**Solution:** Make sure you're using the `-a` flag with the correct password:
```bash
# Get password
kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d

# Use --no-auth-warning to suppress warning messages
redis-cli -h <NLB-DNS> -p 12000 -a <password> --no-auth-warning PING
```

### kubectl Commands Fail from Bastion

**Symptoms:** `Unable to locate credentials` or `error: You must be logged in to the server (Unauthorized)`

**Possible causes:**
1. **IAM credentials not yet available** - The instance profile credentials can take 5-10 seconds to become available after instance launch
2. **kubectl not auto-configured** - Check `/var/log/user-data.log` for kubectl configuration errors

**Solution:**
```bash
# Check if IAM credentials are available
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# Manually reconfigure kubectl if needed
aws eks update-kubeconfig --region <your-region> --name <cluster-name>

# Test kubectl access
kubectl get nodes
```

### Port Already Exists Error

**Symptoms:** `Error from server: ports[X] already exists`

**Explanation:** The port is already exposed on the NLB service.

**Solution:** This is not an error - the port is already configured. Proceed to testing.

### Database Not Ready

**Symptoms:** `connection refused` when testing from inside cluster

**Solution:** Check database status:
```bash
kubectl get redb demo -n redis-enterprise
kubectl describe redb demo -n redis-enterprise
```

Wait for status to show `Active` with `Running` condition.

## Quick Reference

**Get all connection info in one command (from local machine):**
```bash
echo "=== CONNECTION INFO ==="
echo "Bastion SSH: $(terraform output -raw bastion_ssh_command)"
echo "NLB DNS: $(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
echo "Password: $(kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d)"
echo "Port: $(kubectl get redb demo -n redis-enterprise -o jsonpath='{.spec.port}')"
echo "NLB Ports: $(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[*].port}')"
```

**Get connection info from bastion (kubectl already configured):**
```bash
# SSH to bastion first
ssh -i ~/.ssh/your-key.pem ubuntu@<bastion-ip>

# Then get connection info
NLB_DNS=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
PASSWORD=$(kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d)
PORT=$(kubectl get redb demo -n redis-enterprise -o jsonpath='{.spec.port}')

echo "NLB DNS: $NLB_DNS"
echo "Password: $PASSWORD"
echo "Port: $PORT"

# Test immediately
redis-cli -h $NLB_DNS -p $PORT -a $PASSWORD --no-auth-warning PING
```

**Test command template:**
```bash
redis-cli -h $(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}') \
  -p 12000 \
  -a $(kubectl get secret demo-password -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d) \
  --no-auth-warning PING
```

## Port Exposure Verification

The terraform module now includes automatic verification to ensure ports are actually exposed on the NLB service:

- **Pre-check:** Verifies if port already exists before patching
- **Post-verification:** Confirms port was successfully added
- **Error handling:** Terraform will fail with clear error message if port exposure fails

If terraform apply fails with a port exposure error, check:
1. kubectl access is working from your local machine
2. NGINX Ingress controller is running (`kubectl get pods -n ingress-nginx`)
3. No conflicting port mappings exist

The port exposure process is now reliable and will catch errors during terraform apply.

## Summary Checklist

- [ ] Get bastion SSH command, NLB DNS, database password, and port (can use kubectl from local machine or bastion)
- [ ] Verify port is exposed on NLB service (manually patch if needed)
- [ ] Verify TCP ConfigMap has database mapping
- [ ] **Wait 30 seconds** for NLB propagation
- [ ] SSH to bastion
- [ ] Test with redis-cli using NLB DNS and password
- [ ] Confirm `PONG` response

**Remember:** kubectl is automatically configured on the bastion via IAM instance profile - you can run kubectl commands from either your local machine or the bastion.
