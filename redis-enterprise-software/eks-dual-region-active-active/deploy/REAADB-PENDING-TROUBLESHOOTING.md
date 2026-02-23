# REAADB Pending State Troubleshooting Guide

This guide addresses the most common deployment issue: **REAADB stays in pending state**.

## Root Cause

**Big picture:** REAADB stays pending when the operator can't reliably talk to the remote REC API on port 9443 (usually via LB:443) or when the RERCs aren't truly healthy.

## Quick Start

```bash
# Interactive troubleshooting
cd deploy/scripts
./troubleshoot-reaadb-pending.sh ../values-region1.yaml

# Run specific step
./troubleshoot-reaadb-pending.sh ../values-region1.yaml 1  # Validate RERCs
./troubleshoot-reaadb-pending.sh ../values-region1.yaml 2  # Test connectivity
./troubleshoot-reaadb-pending.sh ../values-region1.yaml 5  # Inspect pending state

# Collect diagnostics for support
./troubleshoot-reaadb-pending.sh ../values-region1.yaml collect
```

## Troubleshooting Steps (In Order)

### Step 1: Validate RERCs on Both Sides

**Why:** RERCs must be healthy before REAADB can be created.

**Commands:**
```bash
# On each cluster
kubectl get rerc -n redis-enterprise --context=region1
kubectl describe rerc <rerc-name> -n redis-enterprise --context=region1
```

**Healthy RERC should show:**
- ✅ `Status: Active`
- ✅ `Spec Status: Valid`
- ✅ When used by REAADBs: `Replication Status: up`

**If Status is anything else:**
- Read the Events section
- Check operator logs for that RERC
- Verify `spec.recName` + `spec.recNamespace` match the local REC
- Verify secret `redis-enterprise-<rerc-name>` contains correct admin credentials

**Common issues:**
- ❌ RERC shows `Status: Invalid` → Check secret credentials
- ❌ RERC shows `Status: Pending` → Check network connectivity to remote cluster
- ❌ Missing secret → Create secret with correct REC admin username/password

---

### Step 2: Test 9443 and 443 Exactly Like the Operator

**Why:** The operator/RERC controller does HTTPS calls to validate connectivity. You're seeing 401s and "connection reset by peer" errors on these URLs.

**The operator makes these calls:**
- `GET https://<api-fqdn>/v1/nodes/1` (via LB:443)
- `GET https://<rec-service>:9443/v1/...` (inside the cluster)

#### Test 1: From operator pod to remote API FQDN (port 443)

```bash
# From cluster A, test cluster B's API FQDN
kubectl exec -n redis-enterprise deploy/redis-enterprise-operator --context=region1 -- \
  curl -vk https://<remote-api-fqdn>/v1/nodes/1
```

**Interpretation:**
- ✅ **200 OK + JSON** → network + LB + TLS OK, credentials OK
- ❌ **401** → TLS is fine, but RERC secret creds are wrong for that REC admin
- ❌ **timeout / reset by peer** → 443/9443 path problem (LB, firewall, or ClusterIP)

#### Test 2: From REC pod to its own 9443 (bypass LB)

```bash
# Test direct access to REC service
kubectl exec -n redis-enterprise redis-enterprise-0 -c redis-enterprise-node --context=region1 -- \
  curl -vk https://redis-enterprise.redis-enterprise.svc.cluster.local:9443/v1/nodes/1
```

**Or use port-forward:**
```bash
kubectl port-forward -n redis-enterprise svc/redis-enterprise 9443:9443 &
curl -vk https://127.0.0.1:9443/v1/nodes/1
```

**Diagnosis:**
- ✅ If 9443 direct works but 443 FQDN fails → **LB / firewall / NAT issue**
- ❌ If both fail → **Fix REC networking first**

---

### Step 3: Check LB + NAT Hairpin Assumptions

**Why:** The RERC controller periodically connects to the REC via its external address (the API FQDN/LB). Redis explicitly requires that the LB supports **NAT hairpinning** for this to work.

**Requirements:**
1. ✅ API LB forwards `443 → rec service 9443` on all nodes
2. ✅ Security groups/firewalls allow 443 between clusters
3. ✅ Hairpin traffic from inside the same cluster back to the LB is allowed (or disable IP preservation per cloud LB docs)
4. ✅ DNS for the API FQDN used in `spec.apiFqdnUrl` resolves from operator pods in all clusters

**Test DNS resolution:**
```bash
kubectl exec -n redis-enterprise deploy/redis-enterprise-operator --context=region1 -- \
  nslookup <api-fqdn>
```

**Check load balancers:**
```bash
kubectl get svc -n redis-enterprise --context=region1 | grep LoadBalancer
kubectl get ingress -n redis-enterprise --context=region1
```

**If hairpin isn't possible:**
- Point `apiFqdnUrl` at a reachable internal endpoint instead (e.g., internal LB or route that operator pods can hit)

---

### Step 4: Sanity-Check REAADB Creation Semantics

**Quick checklist:**

✅ **RERC YAMLs:** Applied on **BOTH** clusters (each cluster knows about the other via RERC)

✅ **REAADB YAML:** Applied on **ONE** cluster only; operator will create the corresponding CRDB and propagate the REAADB resource to the peer

✅ **Namespace layout:** Use one shared namespace per cluster (REC, RERC, REAADB all there) until it's working
- There are known edge-cases when REAADB lives only in other namespaces

✅ **Unique names:** Ensure cluster names + namespaces are unique per cluster, not identical on both sides
- This has bitten customers before

**Avoid in early troubleshooting:**
- ❌ REAADB in different namespace than REC/RERC
- ❌ Identical cluster names on both sides
- ❌ Applying REAADB to both clusters

---

### Step 5: Inspect Why the REAADB is Pending

**On the cluster where you applied the REAADB:**

```bash
kubectl describe reaadb <name> -n redis-enterprise --context=region1
```

**Look at:**
- `Status:` and `Spec Status:`
- `Events` (usually show "failed to observe active-active database state" or similar when 9443/443 are broken)

**Check operator logs:**
```bash
kubectl logs deploy/redis-enterprise-operator -n redis-enterprise --context=region1 | grep -i reaadb -A3 -B3
```

**Common patterns when connectivity is the issue:**
- ❌ `Failed executing HTTP request ... Get "https://<api-fqdn>/v1/nodes/1": read ...:443: read: connection reset by peer`
- ❌ `could not get existing active-active database from RedisEnterpriseCluster ... /v1/crdbs/<guid> ... read: connection reset by peer`

**Resolution:**
Once 9443/443 and RERC status are clean, the REAADB usually transitions from `pending → active` on its own.

---

## Diagnostic Collection for Support

The script can automatically collect all necessary diagnostic output:

```bash
./troubleshoot-reaadb-pending.sh ../values-region1.yaml collect
```

**This collects:**
1. `kubectl describe rerc` from each side
2. `kubectl describe reaadb`
3. Operator logs from both clusters
4. `curl -vk https://<api-fqdn>/v1/nodes/1` output from both directions

All files are saved to a timestamped directory: `reaadb-diagnostics-YYYYMMDD-HHMMSS/`

Share this directory when requesting support.

---

## Common Error Patterns

### Error: "connection reset by peer" on port 443

**Cause:** Load balancer or firewall blocking traffic

**Fix:**
1. Verify LB is configured to forward 443 → 9443
2. Check security groups allow 443 between clusters
3. Test with `curl -vk` from operator pod
4. Check LB health checks are passing

### Error: 401 Unauthorized

**Cause:** RERC secret has wrong credentials

**Fix:**
```bash
# Check secret exists
kubectl get secret redis-enterprise-<rerc-name> -n redis-enterprise

# Verify credentials match REC admin user
kubectl get secret redis-enterprise-<rerc-name> -n redis-enterprise -o jsonpath='{.data.username}' | base64 -d
kubectl get secret redis-enterprise-<rerc-name> -n redis-enterprise -o jsonpath='{.data.password}' | base64 -d

# Update if needed
kubectl delete secret redis-enterprise-<rerc-name> -n redis-enterprise
kubectl create secret generic redis-enterprise-<rerc-name> \
  --from-literal=username=admin@redis.com \
  --from-literal=password=<correct-password> \
  -n redis-enterprise
```

### Error: RERC shows "Status: Invalid"

**Causes:**
- Wrong `spec.recName` or `spec.recNamespace`
- Secret doesn't exist or has wrong credentials
- Network connectivity issues

**Fix:**
1. Verify RERC spec matches local REC
2. Verify secret exists and has correct credentials
3. Test connectivity with curl from operator pod

---

## Summary

The troubleshooting flow for REAADB pending:

1. **Validate RERCs** → Must show `Status: Active`, `Spec Status: Valid`
2. **Test 443/9443** → Operator must be able to reach remote REC API
3. **Check LB/NAT** → Hairpinning must work, or use internal endpoint
4. **Verify semantics** → RERCs on both, REAADB on one, unique names
5. **Inspect logs** → Look for connection errors in operator logs

Once connectivity and RERCs are healthy, REAADB transitions to active automatically.

