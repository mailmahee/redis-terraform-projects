# Redis Enterprise Active-Active Monitoring UI

Flask-based web UI for monitoring Redis Enterprise Active-Active (CRDB) clusters across dual regions.

## Features

- 🌍 **Dual-Region Monitoring** - Monitor both us-east-1 and us-west-2 from single UI
- 🔄 **Auto-Refresh** - Configurable refresh interval (default: 5 seconds)
- 📊 **Real-Time Metrics** - Cluster health, database status, replication lag
- 🎯 **CRDB Focus** - Monitors `micron-crdb-prod` Active-Active database
- 🔐 **Secure** - Uses Kubernetes secrets for API authentication
- 🚀 **Lightweight** - 0.5 vCPU, 512MB RAM

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Local Machine                        │
│                                                         │
│  kubectl port-forward svc/redis-monitoring-ui 8080:5000 │
│                          │                              │
│                    http://localhost:8080                │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│              redis-enterprise namespace                 │
│                                                         │
│  ┌─────────────────────────────────────────────┐       │
│  │   Flask Monitoring UI Pod                   │       │
│  │   - Queries both region APIs                │       │
│  │   - Displays cluster + CRDB status          │       │
│  │   - Auto-refresh every 5s                   │       │
│  └─────────────────────────────────────────────┘       │
│                     │              │                    │
│                     ▼              ▼                    │
│         ┌──────────────┐  ┌──────────────┐            │
│         │ rec-us-east-1│  │ rec-us-west-2│            │
│         │   (secret)   │  │   (secret)   │            │
│         └──────────────┘  └──────────────┘            │
└─────────────────────────────────────────────────────────┘
                     │              │
                     ▼              ▼
        ┌────────────────┐  ┌────────────────┐
        │   Region 1     │  │   Region 2     │
        │   us-east-1    │  │   us-west-2    │
        │                │  │                │
        │ api.region1... │  │ api.region2... │
        └────────────────┘  └────────────────┘
```

## Prerequisites

✅ Both Redis Enterprise clusters deployed and healthy  
✅ Active-Active CRDB `micron-crdb-prod` created  
✅ Secrets `rec-us-east-1` and `rec-us-west-2` exist in `redis-enterprise` namespace  
✅ kubectl configured with contexts `region1-new` and `region2-new`

## Quick Start

### Deploy to Region 1 (Default)

```bash
cd redis-enterprise-software/eks-dual-region-active-active/post-deployment/04-redis-monitoring-ui

# Deploy
./deploy.sh

# Access UI
kubectl port-forward -n redis-enterprise svc/redis-monitoring-ui 8080:5000 --context region1-new

# Open browser
open http://localhost:8080
```

### Deploy to Region 2

```bash
# Edit config.yaml
vim config.yaml
# Change: deployment_region: region2

# Deploy
./deploy.sh

# Access UI
kubectl port-forward -n redis-enterprise svc/redis-monitoring-ui 8080:5000 --context region2-new
```

## Configuration

Edit `config.yaml`:

```yaml
# Deployment configuration
deployment_region: region1  # or region2
namespace: redis-enterprise
refresh_interval: 5  # seconds

# Database to monitor
database_name: micron-crdb-prod

# Region configurations
regions:
  region1:
    name: us-east-1
    api_endpoint: api.region1.redis.micron.internal
    secret_name: rec-us-east-1
    context: region1-new
  
  region2:
    name: us-west-2
    api_endpoint: api.region2.redis.micron.internal
    secret_name: rec-us-west-2
    context: region2-new

# Resource limits
resources:
  cpu: 500m
  memory: 512Mi
```

## UI Features

### Dashboard View

- **Cluster Status** - Health, nodes, memory, CPU
- **CRDB Status** - Replication status, sync lag, conflicts
- **Database Metrics** - Ops/sec, memory usage, connections
- **Region Comparison** - Side-by-side metrics

### Auto-Refresh

- Configurable interval (default: 5 seconds)
- Can be changed from UI dropdown
- Persists in browser session

## API Endpoints

The Flask app exposes:

- `GET /` - Main dashboard
- `GET /api/cluster/<region>` - Cluster status JSON
- `GET /api/database/<region>` - Database status JSON
- `GET /api/crdb` - CRDB replication status JSON
- `GET /health` - Health check

## Troubleshooting

### Pod not starting

```bash
# Check pod status
kubectl get pods -n redis-enterprise -l app=redis-monitoring-ui --context region1-new

# Check logs
kubectl logs -n redis-enterprise -l app=redis-monitoring-ui --tail=100 --context region1-new

# Check events
kubectl describe pod -n redis-enterprise -l app=redis-monitoring-ui --context region1-new
```

### Cannot connect to API

```bash
# Test API connectivity from pod
kubectl exec -n redis-enterprise -it <pod-name> --context region1-new -- \
  curl -k https://api.region1.redis.micron.internal:9443/v1/cluster

# Check secrets exist
kubectl get secret rec-us-east-1 -n redis-enterprise --context region1-new
kubectl get secret rec-us-west-2 -n redis-enterprise --context region2-new
```

### Port-forward not working

```bash
# Check service exists
kubectl get svc redis-monitoring-ui -n redis-enterprise --context region1-new

# Try different port
kubectl port-forward -n redis-enterprise svc/redis-monitoring-ui 9090:5000 --context region1-new
```

## Uninstall

```bash
./undeploy.sh
```

## Files

- `config.yaml` - Configuration file
- `app/app.py` - Flask application
- `app/templates/index.html` - Dashboard UI
- `k8s/rbac.yaml` - ServiceAccount and RBAC
- `k8s/deployment.yaml` - Deployment manifest
- `k8s/service.yaml` - Service manifest
- `deploy.sh` - Deployment script
- `undeploy.sh` - Cleanup script

## Next Steps

- Add Grafana integration
- Export metrics to Prometheus
- Add alerting capabilities
- Create custom dashboards per use case