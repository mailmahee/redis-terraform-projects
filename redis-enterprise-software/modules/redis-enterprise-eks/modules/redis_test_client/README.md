# Redis Test Client Module

Deploys a Kubernetes pod with Redis testing tools for validating connectivity and performance of Redis Enterprise databases.

## Features

- ✅ **redis-cli** - Interactive Redis command-line client
- ✅ **redis-benchmark** - Built-in Redis performance testing tool
- ✅ **memtier_benchmark** - Advanced Redis/Memcached benchmark tool (latest version from GitHub)
- ✅ **t3.micro sizing** - Resource-efficient testing (1 vCPU, 1GB RAM)
- ✅ **Auto-configured** - Environment variables pre-set for database connection
- ✅ **Helper scripts** - Optional ConfigMap with common test commands

## Quick Start

### Enable in terraform.tfvars

```hcl
# Deploy test client pod
create_test_client = true
```

### Deploy

```bash
terraform apply
```

### Usage

```bash
# Get pod name
kubectl get pods -n redis-enterprise -l app=redis-test-client

# Connect to pod
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- bash

# Inside pod - environment variables are already set:
# $REDIS_HOST, $REDIS_PORT, $REDIS_PASSWORD

# Test connection
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD ping

# Set/get values
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD set mykey "Hello Redis"
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD get mykey

# Run redis-benchmark
redis-benchmark -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD \
  -t set,get -n 10000 -c 10

# Run memtier_benchmark
memtier_benchmark --server=$REDIS_HOST --port=$REDIS_PORT -a $REDIS_PASSWORD \
  --protocol=redis --clients=10 --threads=2 --ratio=1:10 \
  --data-size=32 --key-pattern=R:R --requests=10000
```

## Configuration Options

### Resource Sizing

Default is t3.micro equivalent (1 vCPU, 1GB RAM). Customize in terraform.tfvars:

```hcl
test_client_cpu_request    = "500m"   # CPU request
test_client_cpu_limit      = "1000m"  # CPU limit (1 vCPU)
test_client_memory_request = "512Mi"  # Memory request
test_client_memory_limit   = "1Gi"    # Memory limit (1GB)
```

### Disable Test Client

```hcl
create_test_client = false
```

## What Gets Deployed

### Kubernetes Resources

- **Deployment**: `redis-test-client` (1 replica)
- **Init Container**: Builds and installs memtier_benchmark from source
- **Main Container**: redis:latest with redis-cli, redis-benchmark
- **ConfigMap** (optional): Helper scripts for common testing patterns

### Container Details

**Base Image**: `redis:latest`
- Includes redis-cli
- Includes redis-benchmark
- Lightweight Alpine Linux base

**Init Container**: `ubuntu:22.04`
- Installs build tools
- Clones memtier_benchmark from GitHub
- Compiles and installs latest version
- Copies binary to shared volume

**Resource Limits**: t3.micro equivalent
- CPU Request: 500m (0.5 vCPU)
- CPU Limit: 1000m (1 vCPU)
- Memory Request: 512Mi
- Memory Limit: 1Gi

## Common Testing Scenarios

### 1. Basic Connectivity Test

```bash
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- \
  redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD ping
```

### 2. Quick Performance Test

```bash
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- \
  redis-benchmark -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD \
  -t set,get -n 10000 -c 10 -q
```

### 3. Advanced Load Test with memtier

```bash
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- \
  memtier_benchmark --server=$REDIS_HOST --port=$REDIS_PORT -a $REDIS_PASSWORD \
  --protocol=redis --clients=50 --threads=4 --ratio=1:10 \
  --data-size=1024 --key-pattern=R:R --requests=100000 --run-count=3
```

### 4. Interactive Shell Session

```bash
# Connect to pod
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- bash

# Inside pod, run multiple tests
redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD <<EOF
SET counter 0
INCR counter
INCR counter
GET counter
EOF
```

## Troubleshooting

### Pod Not Starting

Check init container logs (memtier installation):

```bash
kubectl logs -n redis-enterprise -l app=redis-test-client -c install-memtier
```

### Connection Issues

Verify environment variables:

```bash
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- env | grep REDIS
```

### memtier_benchmark Not Found

Check if binary was installed:

```bash
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- which memtier_benchmark
kubectl exec -it -n redis-enterprise deploy/redis-test-client -- ls -la /memtier/
```

## Module Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| deployment_name | Name of deployment | string | "redis-test-client" | no |
| namespace | Kubernetes namespace | string | "redis-enterprise" | no |
| redis_host | Redis service hostname | string | - | yes |
| redis_port | Redis service port | number | 12000 | no |
| redis_password | Redis password | string | - | yes |
| cpu_request | CPU request | string | "500m" | no |
| cpu_limit | CPU limit | string | "1000m" | no |
| memory_request | Memory request | string | "512Mi" | no |
| memory_limit | Memory limit | string | "1Gi" | no |
| create_test_scripts | Create helper scripts ConfigMap | bool | true | no |

## Module Outputs

| Name | Description |
|------|-------------|
| deployment_name | Name of the test client deployment |
| namespace | Namespace where deployed |
| pod_selector | Label selector for finding pods |
| usage_instructions | How to use the test client |

## Resource Costs

**t3.micro equivalent**:
- AWS EC2: ~$0.0104/hour = ~$7.50/month
- EKS pod: Minimal (uses existing node capacity)

The test client is designed to be lightweight and can run on existing cluster nodes without requiring additional infrastructure.

## References

- [redis-cli documentation](https://redis.io/docs/connect/cli/)
- [redis-benchmark documentation](https://redis.io/docs/management/optimization/benchmarks/)
- [memtier_benchmark GitHub](https://github.com/RedisLabs/memtier_benchmark)
- [Redis Enterprise on Kubernetes](https://redis.io/docs/latest/operate/kubernetes/)
