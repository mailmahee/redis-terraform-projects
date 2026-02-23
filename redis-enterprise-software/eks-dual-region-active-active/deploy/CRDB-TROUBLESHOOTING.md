# CRDB (Active-Active) Troubleshooting Guide

This guide provides a structured approach to troubleshooting Redis Enterprise Active-Active (CRDB) databases on Kubernetes, based on the official Redis Enterprise CRDB-on-K8s runbook.

## Quick Start

Use the automated troubleshooting script:

```bash
# Interactive mode
cd deploy/scripts
./troubleshoot-crdb.sh ../values-region1.yaml

# Run specific step
./troubleshoot-crdb.sh ../values-region1.yaml 0  # Identify CRDB
./troubleshoot-crdb.sh ../values-region1.yaml 1  # K8s health
./troubleshoot-crdb.sh ../values-region1.yaml 2  # REC health
./troubleshoot-crdb.sh ../values-region1.yaml 3  # Syncer state
./troubleshoot-crdb.sh ../values-region1.yaml 4  # Network
./troubleshoot-crdb.sh ../values-region1.yaml 5  # TLS/certs
./troubleshoot-crdb.sh ../values-region1.yaml 6  # Connectivity

# Run all steps
./troubleshoot-crdb.sh ../values-region1.yaml all
```

## Troubleshooting Flow

The recommended troubleshooting flow follows this order:

```
kubectl (CRDs/events/logs) 
  → rladmin status + rlcheck 
  → crdb-cli crdb status on each REC 
  → validate inter-REC network (DNS/LB/ports) 
  → validate AA TLS/syncer certs 
  → redis-cli INFO/CRDT & ping tests
```

## Step-by-Step Guide

### Step 0: Identify CRDB & Participants

**Purpose:** Confirm the CRDB exists, identify participating clusters, and check high-level sync state.

**Commands:**
```bash
# List all CRDBs
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb list

# Check specific CRDB status
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb status --crdb-guid <CRDB_GUID>

# Get CRDB GUID from REAADB resource
kubectl get reaadb aadb-sample -n redis-enterprise --context=region1 \
  -o jsonpath='{.status.replicaSourceStatuses[*].guid}'
```

**What to look for:**
- CRDB exists and is recognized by all participating clusters
- All participants are listed
- High-level sync state shows clusters are communicating

---

### Step 1: Check K8s / Operator Health

**Purpose:** Verify Kubernetes resources, operator health, and check for errors in events/logs.

**Commands:**
```bash
# View all resources
kubectl get rec,reaadb,rerc,pods,svc -n redis-enterprise --context=region1

# Describe REAADB
kubectl describe reaadb aadb-sample -n redis-enterprise --context=region1

# Check recent events
kubectl get events -n redis-enterprise --context=region1 --sort-by=.lastTimestamp

# View operator logs
kubectl logs deploy/redis-enterprise-operator -n redis-enterprise --context=region1
```

**What to look for:**
- AA controller errors
- Webhook/TLS issues
- "connectivity check failed" or "replication link down" events
- REAADB status shows all participants as Active
- RERCs are in Active state

---

### Step 2: Check REC & DB Health

**Purpose:** Verify cluster and database health from inside the REC pod.

**Commands:**
```bash
# Cluster + DB health
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  rladmin status extra all

# Node-level checks
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  rlcheck --continue-on-error
```

**What to look for:**
- `rladmin status` is the primary view for nodes/DBs/endpoints
- CRDB DB shows status OK
- All endpoints are up
- `rlcheck` validates services, ports, host settings, TCP connectivity, encrypted gossip
- No node health issues

---

### Step 3: Verify CRDB Syncer State

**Purpose:** Check replication sync status between participating clusters.

**Commands:**
```bash
# Check CRDB status on each participating cluster
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb status --crdb-guid <CRDB_GUID>

kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region2 -- \
  crdb-cli crdb status --crdb-guid <CRDB_GUID>

# Check CRDT info from database endpoint
redis-cli -h <db-endpoint> -p <port> info crdt
```

**What to look for:**
- All participants show syncing/online
- No repeated failures
- Replication backlog is not consistently full (may need tuning)
- CRDT section in INFO shows healthy replication metrics

**If lagging:**
```bash
# Tune backlog sizes if needed
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb update --crdb-guid <CRDB_GUID> --replication-backlog-size <size>
```

---

### Step 4: Check Inter-Cluster Network

**Purpose:** Validate network connectivity between clusters for CRDB replication.

**Requirements:**
- AA on K8s requires working network paths between RECs
- Network access must exist for replication endpoints
- If path isn't there, sync fails

**Commands:**
```bash
# Test API ingress (for operator AA controller/crdb-cli)
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  curl -vk https://<api-hostname>

# Test replication endpoint/hostname
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  openssl s_client -connect <replication-hostname>:443 -servername <replication-hostname>

# DNS resolution test
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  nslookup <api-hostname>
```

**What to validate:**
- DNS resolution for API + replication hostnames
- Firewall/LB allows the AA replication port(s)
- External load balancers have all REC nodes in pool
- No health-check issues on load balancers
- Network path exists between clusters

---

### Step 5: Check TLS / Cert Issues

**Purpose:** Verify TLS configuration and certificate validity for CRDB replication.

**Common Issue:** Expired/mismatched syncer certs are a very common cause of "replication link is down"

**Commands:**
```bash
# Check if TLS is enabled for AA cluster connections
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb status --crdb-guid <CRDB_GUID>

# Force CRDB to re-bind after cert updates
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  crdb-cli crdb update --crdb-guid <CRDB_GUID> --force
```

**What to check:**
- Proxy/syncer certs are valid, not expired
- Key size is OK
- If certs were updated, follow cert-rotation steps
- After cert rotation, force CRDB to re-bind with `--force` flag

---

### Step 6: End-to-End Data-Plane Connectivity

**Purpose:** Test actual data-plane connectivity to isolate service vs ingress issues.

**Commands:**
```bash
# Test direct service (bypass ingress)
kubectl port-forward -n redis-enterprise svc/<db-svc> 16441:16441 &
redis-cli -h 127.0.0.1 -p 16441 ping

# Test through ingress/LB with TLS + SNI
redis-cli -h <db-hostname> -p 443 --tls --sni <db-hostname> --insecure ping

# List database services
kubectl get svc -n redis-enterprise --context=region1 | grep database
```

**What this isolates:**
- Service/ClusterIP issues vs ingress/LB issues
- TLS/SNI misconfig vs raw TCP problems
- Whether the database is reachable at all

---

## Common Issues & Solutions

### Issue: "Replication link is down"

**Most common causes:**
1. Expired or mismatched syncer certificates (Step 5)
2. Network connectivity issues between clusters (Step 4)
3. Firewall blocking replication ports (Step 4)
4. Load balancer health check failures (Step 4)

**Resolution:**
1. Check cert expiration dates
2. Force CRDB to re-bind: `crdb-cli crdb update --crdb-guid <GUID> --force`
3. Verify network path with `curl` and `openssl s_client`
4. Check load balancer configuration and health checks

### Issue: CRDB shows "lagging" or high backlog

**Causes:**
- Replication backlog too small for write rate
- Network bandwidth limitations
- Cluster resource constraints

**Resolution:**
```bash
# Increase replication backlog size
crdb-cli crdb update --crdb-guid <CRDB_GUID> --replication-backlog-size <larger-size>
```

### Issue: REAADB stuck in "pending" state

**Check:**
1. RERCs are Active (Step 1)
2. Operator logs for errors (Step 1)
3. Network connectivity between clusters (Step 4)
4. No orphaned databases blocking creation

**Resolution:**
```bash
# Check REAADB status
kubectl describe reaadb aadb-sample -n redis-enterprise

# Check operator logs
kubectl logs deploy/redis-enterprise-operator -n redis-enterprise --tail=100

# Verify RERCs
kubectl get rerc -n redis-enterprise
```

## Official Documentation

- [Redis Enterprise Troubleshooting Hub](https://redis.io/docs/latest/operate/rs/references/cli-utilities/)
- [rlcheck Reference](https://redis.io/docs/latest/operate/rs/references/cli-utilities/rlcheck/)
- [rladmin status Reference](https://redis.io/docs/latest/operate/rs/references/cli-utilities/rladmin/status/)
- [K8s Active-Active Documentation](https://redis.io/docs/latest/operate/kubernetes/active-active/)

## Summary

The short "go-to" for K8s CRDB troubleshooting:

1. **kubectl** (CRDs/events/logs)
2. **rladmin status + rlcheck**
3. **crdb-cli crdb status** on each REC
4. **Validate inter-REC network** (DNS/LB/ports)
5. **Validate AA TLS/syncer certs**
6. **redis-cli INFO/CRDT & ping tests**

Use the automated script (`troubleshoot-crdb.sh`) to walk through these steps systematically.

