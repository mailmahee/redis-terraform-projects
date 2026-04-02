apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: redis-enterprise-alerts
  namespace: monitoring
  labels:
    app.kubernetes.io/managed-by: terraform
spec:
  groups:
    - name: redis-enterprise
      rules:
        - alert: RedisHighMemoryUsage
          expr: redis_used_memory / redis_maxmemory * 100 > ${alert_redis_memory_threshold}
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Redis memory usage above ${alert_redis_memory_threshold}%"

        - alert: RedisHighCPUUsage
          expr: rate(redis_cpu_sys_seconds_total[5m]) * 100 > ${alert_redis_cpu_threshold}
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Redis CPU usage above ${alert_redis_cpu_threshold}%"

        - alert: RedisHighConnectionCount
          expr: redis_connected_clients > ${alert_redis_connection_threshold}
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Redis connections above ${alert_redis_connection_threshold}"

