#!/bin/bash
# Troubleshooting helper for Redis Enterprise Active-Active deployment
# Usage: ./troubleshoot.sh <values-file> [command]

set -e

VALUES_FILE=$1
COMMAND=$2

if [ -z "$VALUES_FILE" ]; then
  echo "Usage: $0 <values-file> [command]"
  echo ""
  echo "Available commands:"
  echo "  rlcheck              - Run rlcheck to verify node health"
  echo "  status               - Show cluster status (rladmin status)"
  echo "  status-all           - Show detailed cluster status (rladmin status extra all)"
  echo "  status-dbs           - Show database status"
  echo "  status-nodes         - Show node status"
  echo "  status-shards        - Show shard status"
  echo "  status-endpoints     - Show endpoint status"
  echo "  list-dbs             - List all databases via REST API"
  echo "  rec-logs             - Show REC pod logs"
  echo "  operator-logs        - Show operator logs"
  echo "  describe-rec         - Describe REC resource"
  echo "  describe-rerc        - Describe RERC resources"
  echo "  describe-reaadb      - Describe REAADB resource"
  echo "  events               - Show recent events in namespace"
  echo "  shell                - Open shell in REC pod"
  echo ""
  echo "If no command is specified, shows interactive menu"
  exit 1
fi

if [ ! -f "$VALUES_FILE" ]; then
  echo "ERROR: Values file not found: $VALUES_FILE"
  exit 1
fi

# Load configuration
if ! command -v yq &> /dev/null; then
  echo "ERROR: yq is required but not installed."
  exit 1
fi

K8S_CONTEXT=$(yq eval '.cluster.k8s_context' "$VALUES_FILE")
NAMESPACE=$(yq eval '.rec.namespace' "$VALUES_FILE")
REC_NAME=$(yq eval '.rec.name' "$VALUES_FILE")
CLUSTER_NAME=$(yq eval '.cluster.name' "$VALUES_FILE")

echo "Cluster: $CLUSTER_NAME"
echo "Context: $K8S_CONTEXT"
echo "Namespace: $NAMESPACE"
echo ""

# Function to execute commands in REC pod
exec_rec() {
  kubectl exec -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- "$@"
}

# Execute command based on input
case "$COMMAND" in
  rlcheck)
    echo "=== Running rlcheck ==="
    exec_rec rlcheck
    ;;
    
  status)
    echo "=== Cluster Status ==="
    exec_rec rladmin status
    ;;
    
  status-all)
    echo "=== Detailed Cluster Status ==="
    exec_rec rladmin status extra all
    ;;
    
  status-dbs)
    echo "=== Database Status ==="
    exec_rec rladmin status databases extra all
    ;;
    
  status-nodes)
    echo "=== Node Status ==="
    exec_rec rladmin status nodes extra all
    ;;
    
  status-shards)
    echo "=== Shard Status ==="
    exec_rec rladmin status shards extra all
    ;;
    
  status-endpoints)
    echo "=== Endpoint Status ==="
    exec_rec rladmin status endpoints extra all
    ;;
    
  list-dbs)
    echo "=== Databases (via REST API) ==="
    exec_rec bash -c "curl -k -s -u admin@redis.com:RedisTest123 https://localhost:9443/v1/bdbs | jq ."
    ;;
    
  rec-logs)
    echo "=== REC Pod Logs (last 100 lines) ==="
    kubectl logs -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" --tail=100
    ;;
    
  operator-logs)
    echo "=== Operator Logs (last 100 lines) ==="
    OPERATOR_POD=$(kubectl get pods -n "$NAMESPACE" --context="$K8S_CONTEXT" -l name=redis-enterprise-operator -o jsonpath='{.items[0].metadata.name}')
    kubectl logs -n "$NAMESPACE" "$OPERATOR_POD" --context="$K8S_CONTEXT" --tail=100
    ;;
    
  describe-rec)
    echo "=== REC Resource ==="
    kubectl describe rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT"
    ;;
    
  describe-rerc)
    echo "=== RERC Resources ==="
    kubectl get rerc -n "$NAMESPACE" --context="$K8S_CONTEXT"
    echo ""
    kubectl describe rerc -n "$NAMESPACE" --context="$K8S_CONTEXT"
    ;;
    
  describe-reaadb)
    echo "=== REAADB Resource ==="
    kubectl get reaadb -n "$NAMESPACE" --context="$K8S_CONTEXT"
    echo ""
    kubectl describe reaadb -n "$NAMESPACE" --context="$K8S_CONTEXT"
    ;;
    
  events)
    echo "=== Recent Events ==="
    kubectl get events -n "$NAMESPACE" --context="$K8S_CONTEXT" --sort-by='.lastTimestamp' | tail -20
    ;;
    
  shell)
    echo "=== Opening shell in REC pod ==="
    echo "Type 'exit' to return"
    kubectl exec -it -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- bash
    ;;
    
  *)
    # Interactive menu
    echo "Select troubleshooting command:"
    echo ""
    echo "  1) rlcheck - Verify node health"
    echo "  2) rladmin status - Cluster status"
    echo "  3) rladmin status extra all - Detailed status"
    echo "  4) List databases"
    echo "  5) REC logs"
    echo "  6) Operator logs"
    echo "  7) Describe REC"
    echo "  8) Describe RERCs"
    echo "  9) Recent events"
    echo "  0) Open shell"
    echo ""
    read -p "Enter choice [1-9,0]: " choice
    
    case $choice in
      1) exec_rec rlcheck ;;
      2) exec_rec rladmin status ;;
      3) exec_rec rladmin status extra all ;;
      4) exec_rec bash -c "curl -k -s -u admin@redis.com:RedisTest123 https://localhost:9443/v1/bdbs | jq ." ;;
      5) kubectl logs -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" --tail=100 ;;
      6) 
        OPERATOR_POD=$(kubectl get pods -n "$NAMESPACE" --context="$K8S_CONTEXT" -l name=redis-enterprise-operator -o jsonpath='{.items[0].metadata.name}')
        kubectl logs -n "$NAMESPACE" "$OPERATOR_POD" --context="$K8S_CONTEXT" --tail=100
        ;;
      7) kubectl describe rec "$REC_NAME" -n "$NAMESPACE" --context="$K8S_CONTEXT" ;;
      8) kubectl describe rerc -n "$NAMESPACE" --context="$K8S_CONTEXT" ;;
      9) kubectl get events -n "$NAMESPACE" --context="$K8S_CONTEXT" --sort-by='.lastTimestamp' | tail -20 ;;
      0) kubectl exec -it -n "$NAMESPACE" redis-enterprise-0 -c redis-enterprise-node --context="$K8S_CONTEXT" -- bash ;;
      *) echo "Invalid choice" ;;
    esac
    ;;
esac

