apiVersion: v1
kind: Service
metadata:
  name: prometheus-loadbalancer
  namespace: monitoring
  labels:
    environment: ${environment}
    app.kubernetes.io/managed-by: terraform
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: prometheus
  ports:
    - name: web
      port: 9090
      targetPort: 9090

