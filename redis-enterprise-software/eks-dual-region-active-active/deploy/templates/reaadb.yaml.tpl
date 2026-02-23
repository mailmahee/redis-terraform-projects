apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseActiveActiveDatabase
metadata:
  name: ${REAADB_NAME}
  namespace: ${NAMESPACE}
spec:
  participatingClusters:
${PARTICIPATING_CLUSTERS}
  globalConfigurations:
    databaseSecretName: ${SECRET_NAME}
    evictionPolicy: ${EVICTION_POLICY}
    memorySize: ${MEMORY_SIZE}
    replication: ${REPLICATION}
    shardCount: ${SHARD_COUNT}
    type: redis

