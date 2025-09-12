#!/bin/bash

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "📊 Checking Prometheus Metrics Collection"
echo "========================================="

# Port forward Prometheus
echo "Starting port-forward to Prometheus..."
kubectl port-forward -n monitoring svc/prometheus 9091:9090 &>/dev/null &
PF_PID=$!
sleep 3

# Function to check metrics
check_metric() {
    local metric_name=$1
    local description=$2
    
    echo -n "Checking $description... "
    
    local result=$(curl -s "http://localhost:9091/api/v1/query?query=${metric_name}" 2>/dev/null | jq -r '.data.result | length')
    
    if [ "$result" -gt 0 ]; then
        echo -e "${GREEN}✓${NC} Found $result series"
        return 0
    else
        echo -e "${RED}✗${NC} No data"
        return 1
    fi
}

echo ""
echo "ArgoCD Metrics:"
echo "---------------"
check_metric "argocd_app_info" "ArgoCD application info"
check_metric "argocd_app_health_total" "ArgoCD application health"
check_metric "argocd_app_sync_total" "ArgoCD sync operations"
check_metric "argocd_cluster_api_resource_objects" "ArgoCD cluster resources"
check_metric "argocd_cluster_info" "ArgoCD cluster info"

echo ""
echo "Kubernetes Metrics:"
echo "-------------------"
check_metric "up" "Target availability"
check_metric "kube_pod_info" "Kubernetes pod info"
check_metric "kube_node_info" "Kubernetes node info"
check_metric "container_memory_usage_bytes" "Container memory usage"
check_metric "container_cpu_usage_seconds_total" "Container CPU usage"

echo ""
echo "Nginx Sample App Metrics (if deployed):"
echo "----------------------------------------"
check_metric "nginx_connections_active" "Nginx active connections"
check_metric "nginx_connections_accepted" "Nginx accepted connections"
check_metric "nginx_http_requests_total" "Nginx HTTP requests"

# Cleanup
kill $PF_PID 2>/dev/null || true

echo ""
echo "========================================="
echo "💡 Tip: Access Prometheus UI at http://localhost:9090"
echo "       Run: kubectl port-forward -n monitoring svc/prometheus 9090:9090"
