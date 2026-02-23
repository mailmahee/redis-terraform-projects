apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: redis-enterprise-api
  namespace: ${NAMESPACE}
  annotations:
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${API_FQDN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ${REC_NAME}
            port:
              number: 9443

