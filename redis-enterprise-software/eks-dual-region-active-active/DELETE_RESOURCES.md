# How to Delete Redis Enterprise Kubernetes Resources

Reference: https://redis.io/docs/latest/operate/kubernetes/re-clusters/delete-custom-resources/

## ⚡ IMPORTANT: Deletion Order for Faster Terraform Destroy

**Problem:** The current Terraform destroy process deletes CRDs first, which have finalizers that wait for the REC to be deleted. This creates a slow cascade that can take 8-10 minutes just for the CRD/namespace deletion phase.

**Solution:** Delete resources in the proper order BEFORE running `terraform destroy`:

### Recommended Pre-Destroy Cleanup (Saves 5-8 minutes)

Run these commands in **BOTH regions** before `terraform destroy`:

```bash
# Region 1 (us-east-1)
kubectl config use-context arn:aws:eks:us-east-1:ACCOUNT_ID:cluster/ba-r1-redis-enterprise

# 1. Delete REAADBs first
kubectl delete reaadb --all -n redis-enterprise --timeout=60s

# 2. Delete RERCs
kubectl delete rerc --all -n redis-enterprise --timeout=60s

# 3. Delete REDBs (regular databases)
kubectl delete redb --all -n redis-enterprise --timeout=60s

# 4. Delete REC (Redis Enterprise Cluster)
kubectl delete rec redis-enterprise -n redis-enterprise --timeout=120s

# Wait for REC pods to terminate
kubectl wait --for=delete pod -l app=redis-enterprise -n redis-enterprise --timeout=120s

# Region 2 (us-west-2)
kubectl config use-context arn:aws:eks:us-west-2:ACCOUNT_ID:cluster/ba-r2-redis-enterprise

# Repeat the same steps for Region 2
kubectl delete reaadb --all -n redis-enterprise --timeout=60s
kubectl delete rerc --all -n redis-enterprise --timeout=60s
kubectl delete redb --all -n redis-enterprise --timeout=60s
kubectl delete rec redis-enterprise -n redis-enterprise --timeout=120s
kubectl wait --for=delete pod -l app=redis-enterprise -n redis-enterprise --timeout=120s
```

**After cleanup, run:**
```bash
cd redis-enterprise-software/eks-dual-region-active-active
terraform destroy -auto-approve
```

This approach allows the CRDs and namespace to delete quickly since all resources are already gone.

---

## Delete an Active-Active Database (REAADB)

1. On one of the existing participating clusters, delete the REAADB:
```bash
kubectl delete reaadb <reaadb-name>
```

2. Verify the REAADB no longer exists:
```bash
kubectl get reaadb -o=jsonpath='{range .items[*]}{.metadata.name}'
```

### Troubleshoot Stuck REAADB Deletion

If the REAADB is stuck in delete-pending state, you can manually remove the finalizer:

**WARNING**: This may leave orphaned resources that need manual cleanup.

```bash
kubectl patch reaadb <reaadb-name> --type=json -p \
    '[{"op":"remove","path":"/metadata/finalizers"}]'
```

## Delete a Remote Cluster (RERC)

1. Verify the RERC you want to delete isn't listed as a participating cluster in any REAADB resources.
   If an RERC is still listed as a participating cluster in any database, the deletion will be blocked.

2. On one of the existing participating clusters, delete the RERC:
```bash
kubectl delete rerc <rerc-name>
```

3. Verify the RERC no longer exists:
```bash
kubectl get rerc -o=jsonpath='{range .items[*]}{.metadata.name}'
```

## Delete a Database (REDB)

```bash
kubectl delete redb <your-db-name>
```

### Troubleshoot Stuck REDB Deletion

If stuck, manually remove the finalizer:

```bash
kubectl patch redb <your-db-name> --type=json -p \
    '[{"op":"remove","path":"/metadata/finalizers","value":"finalizer.redisenterprisedatabases.app.redislabs.com"}]'
```

## Delete a Redis Enterprise Cluster (REC)

1. Delete all the databases in your cluster first
2. Run:
```bash
kubectl delete rec <your-rec-name>
```

### Troubleshoot Stuck REC Deletion

```bash
kubectl patch rec <your-rec-name> --type=json -p \
    '[{"op":"remove","path":"/metadata/finalizers","value":"redbfinalizer.redisenterpriseclusters.app.redislabs.com"}]'
```

## Manual CRDB Deletion via REST API

If Kubernetes resources are stuck and won't delete, you can delete the underlying CRDB directly:

1. List all CRDBs:
```bash
kubectl exec -it redis-enterprise-0 -n redis-enterprise -- bash -c \
  "curl -k -u admin@redis.com:RedisTest123 https://localhost:9443/v1/crdbs"
```

2. Delete a specific CRDB by GUID:
```bash
kubectl exec -it redis-enterprise-0 -n redis-enterprise -- bash -c \
  "curl -k -u admin@redis.com:RedisTest123 -X DELETE https://localhost:9443/v1/crdbs/<GUID>"
```

## Common Issues

### REAADB Missing Secret Error
If you see `failed to get secret` errors, create the required secret:

```bash
kubectl create secret generic <secret-name> \
  --from-literal=password='YourPassword' \
  -n redis-enterprise
```

The secret name is specified in the REAADB spec under `globalConfigurations.databaseSecretName`.

