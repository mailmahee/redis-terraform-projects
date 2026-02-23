#==============================================================================
# Redis Test Client - Outputs
#==============================================================================

output "deployment_name" {
  description = "Name of the test client deployment"
  value       = kubernetes_deployment.redis_test_client.metadata[0].name
}

output "namespace" {
  description = "Namespace where test client is deployed"
  value       = kubernetes_deployment.redis_test_client.metadata[0].namespace
}

output "pod_selector" {
  description = "Label selector to find the test client pod"
  value       = "app=redis-test-client"
}

output "usage_instructions" {
  description = "Instructions for using the test client"
  value       = <<-EOT

    ========================================================================
    Redis Test Client Deployed Successfully!
    ========================================================================

    Installed tools:
    - redis-cli
    - redis-benchmark
    - memtier_benchmark

    To access the test client:

    1. Get pod name:
       kubectl get pods -n ${kubernetes_deployment.redis_test_client.metadata[0].namespace} -l app=redis-test-client

    2. Connect to pod:
       kubectl exec -it -n ${kubernetes_deployment.redis_test_client.metadata[0].namespace} deploy/${kubernetes_deployment.redis_test_client.metadata[0].name} -- bash

    3. Inside pod - test Redis:
       # Test connection
       redis-cli -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD ping

       # Quick benchmark
       redis-benchmark -h $REDIS_HOST -p $REDIS_PORT -a $REDIS_PASSWORD -t set,get -n 10000 -c 10 -q

       # Memtier benchmark
       memtier_benchmark --server=$REDIS_HOST --port=$REDIS_PORT -a $REDIS_PASSWORD \
         --protocol=redis --clients=10 --threads=2 --requests=10000

    Environment variables pre-configured:
      REDIS_HOST=${var.redis_host}
      REDIS_PORT=${var.redis_port}
      REDIS_PASSWORD=***

    ========================================================================
  EOT
}
