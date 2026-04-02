apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: monitoring
  labels:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/managed-by: terraform
spec:
  replicas: ${grafana_replicas}
  selector:
    matchLabels:
      app.kubernetes.io/name: grafana
  template:
    metadata:
      labels:
        app.kubernetes.io/name: grafana
    spec:
      containers:
        - name: grafana
          image: grafana/grafana:latest
          env:
            - name: GF_SECURITY_ADMIN_PASSWORD
              value: "${grafana_admin_password}"
            - name: GF_SERVER_HTTP_PORT
              value: "3000"
          ports:
            - containerPort: 3000
          resources:
            requests:
              memory: ${grafana_memory_request}
              cpu: ${grafana_cpu_request}
            limits:
              memory: ${grafana_memory_limit}
              cpu: ${grafana_cpu_limit}

