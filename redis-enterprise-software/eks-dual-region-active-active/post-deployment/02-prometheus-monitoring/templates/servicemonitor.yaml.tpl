apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: redis-enterprise
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: terraform
spec:
  selector:
    matchLabels:
      app: redis-enterprise
  endpoints:
    - scheme: ${redis_metrics_scheme}
      path: ${redis_metrics_path}
      interval: ${prometheus_scrape_interval}
      tlsConfig:
        insecureSkipVerify: true
  namespaceSelector:
    any: true

