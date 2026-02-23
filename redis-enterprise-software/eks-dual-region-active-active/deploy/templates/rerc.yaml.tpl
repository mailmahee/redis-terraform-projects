apiVersion: app.redislabs.com/v1alpha1
kind: RedisEnterpriseRemoteCluster
metadata:
  name: ${RERC_NAME}
  namespace: ${NAMESPACE}
spec:
  recName: ${REC_NAME}
  recNamespace: ${NAMESPACE}
  apiFqdnUrl: ${API_FQDN_URL}
  dbFqdnSuffix: ${DB_FQDN_SUFFIX}
  secretName: ${SECRET_NAME}

