apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
  labels:
    cluster: ${cluster_name}
    environment: ${environment}
    region: ${region}
    app.kubernetes.io/managed-by: terraform
spec:
  replicas: ${prometheus_replicas}
  retention: ${prometheus_retention}
  evaluationInterval: ${prometheus_evaluation_interval}
  scrapeInterval: ${prometheus_scrape_interval}
  scrapeTimeout: ${prometheus_scrape_timeout}
  storage:
    volumeClaimTemplate:
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: ${prometheus_storage_size}
  resources:
    requests:
      memory: ${prometheus_memory_request}
      cpu: ${prometheus_cpu_request}
    limits:
      memory: ${prometheus_memory_limit}
      cpu: ${prometheus_cpu_limit}
  serviceAccountName: prometheus
  serviceMonitorSelector: {}
  ruleSelector: {}

