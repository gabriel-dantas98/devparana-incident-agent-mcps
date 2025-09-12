#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(dirname "$SCRIPT_DIR")"
FAILED_TESTS=0
PASSED_TESTS=0

# Helper functions
print_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED_TESTS++))
}

print_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED_TESTS++))
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Test functions
test_cluster_exists() {
    print_test "Checking if Kind cluster exists..."
    if kind get clusters 2>/dev/null | grep -q "^agent-cluster$"; then
        print_pass "Cluster 'agent-cluster' exists"
        return 0
    else
        print_fail "Cluster 'agent-cluster' not found"
        return 1
    fi
}

test_kubectl_context() {
    print_test "Checking kubectl context..."
    if kubectl cluster-info --context kind-agent-cluster &>/dev/null; then
        print_pass "kubectl context is configured correctly"
        return 0
    else
        print_fail "kubectl context not configured"
        return 1
    fi
}

test_argocd_namespace() {
    print_test "Checking ArgoCD namespace..."
    if kubectl get namespace argocd &>/dev/null; then
        print_pass "ArgoCD namespace exists"
        return 0
    else
        print_fail "ArgoCD namespace not found"
        return 1
    fi
}

test_argocd_pods() {
    print_test "Checking ArgoCD pods..."
    local ready_pods=$(kubectl get pods -n argocd -o json | jq '[.items[] | select(.status.phase=="Running")] | length')
    local total_pods=$(kubectl get pods -n argocd -o json | jq '.items | length')
    
    if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
        print_pass "All ArgoCD pods are running ($ready_pods/$total_pods)"
        return 0
    else
        print_fail "Not all ArgoCD pods are running ($ready_pods/$total_pods)"
        kubectl get pods -n argocd --no-headers | while read line; do
            echo "  $line"
        done
        return 1
    fi
}

test_monitoring_namespace() {
    print_test "Checking monitoring namespace..."
    if kubectl get namespace monitoring &>/dev/null; then
        print_pass "Monitoring namespace exists"
        return 0
    else
        print_fail "Monitoring namespace not found"
        return 1
    fi
}

test_prometheus_pod() {
    print_test "Checking Prometheus pod..."
    local pod_status=$(kubectl get pods -n monitoring -l app=prometheus -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [ "$pod_status" = "Running" ]; then
        print_pass "Prometheus is running"
        return 0
    else
        print_fail "Prometheus is not running (status: $pod_status)"
        return 1
    fi
}

test_grafana_pod() {
    print_test "Checking Grafana pod..."
    local pod_status=$(kubectl get pods -n monitoring -l app=grafana -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    
    if [ "$pod_status" = "Running" ]; then
        print_pass "Grafana is running"
        return 0
    else
        print_fail "Grafana is not running (status: $pod_status)"
        return 1
    fi
}

test_argocd_service() {
    print_test "Checking ArgoCD service endpoints..."
    local endpoints=$(kubectl get endpoints argocd-server -n argocd -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    
    if [ -n "$endpoints" ]; then
        print_pass "ArgoCD service has endpoints: $endpoints"
        return 0
    else
        print_fail "ArgoCD service has no endpoints"
        return 1
    fi
}

test_prometheus_service() {
    print_test "Checking Prometheus service endpoints..."
    local endpoints=$(kubectl get endpoints prometheus -n monitoring -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    
    if [ -n "$endpoints" ]; then
        print_pass "Prometheus service has endpoints: $endpoints"
        return 0
    else
        print_fail "Prometheus service has no endpoints"
        return 1
    fi
}

test_grafana_service() {
    print_test "Checking Grafana service endpoints..."
    local endpoints=$(kubectl get endpoints grafana -n monitoring -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
    
    if [ -n "$endpoints" ]; then
        print_pass "Grafana service has endpoints: $endpoints"
        return 0
    else
        print_fail "Grafana service has no endpoints"
        return 1
    fi
}

test_argocd_metrics() {
    print_test "Checking if ArgoCD metrics are exposed..."
    # Use service port-forward to avoid needing curl inside the container
    kubectl -n argocd port-forward svc/argocd-server-metrics 18083:8083 &>/dev/null &
    local pf_pid=$!
    sleep 3
    local metrics=$(curl -s http://localhost:18083/metrics 2>/dev/null | head -n 5)
    kill $pf_pid 2>/dev/null || true
    if echo "$metrics" | grep -q "# HELP"; then
        print_pass "ArgoCD is exposing metrics"
        return 0
    else
        print_fail "ArgoCD metrics endpoint not responding"
        return 1
    fi
}

test_prometheus_targets() {
    print_test "Checking Prometheus targets..."
    
    # Port forward to Prometheus
    kubectl port-forward -n monitoring svc/prometheus 9091:9090 &>/dev/null &
    local pf_pid=$!
    sleep 3
    
    # Check targets
    local targets=$(curl -s http://localhost:9091/api/v1/targets 2>/dev/null | jq -r '.data.activeTargets | length' 2>/dev/null)
    
    kill $pf_pid 2>/dev/null || true
    
    if [ -n "$targets" ] && [ "$targets" -gt 0 ]; then
        print_pass "Prometheus has $targets active targets"
        return 0
    else
        print_fail "Prometheus has no active targets"
        return 1
    fi
}

test_grafana_datasource() {
    print_test "Checking Grafana datasource configuration..."
    local datasource=$(kubectl get configmap grafana-datasources -n monitoring -o jsonpath='{.data.datasources\.yaml}' 2>/dev/null | grep -c "Prometheus")
    
    if [ "$datasource" -gt 0 ]; then
        print_pass "Grafana has Prometheus datasource configured"
        return 0
    else
        print_fail "Grafana Prometheus datasource not configured"
        return 1
    fi
}

test_sample_app() {
    print_test "Deploying sample nginx app for validation..."
    
    # Deploy sample app
    kubectl apply -f "$CLUSTER_DIR/resources/sample-apps/nginx-deployment.yaml" &>/dev/null
    
    # Wait for deployment
    print_info "Waiting for nginx deployment to be ready..."
    if kubectl wait --for=condition=available --timeout=60s deployment/nginx-sample -n sample-apps &>/dev/null; then
        print_pass "Sample nginx app deployed successfully"
        
        # Check if metrics are being scraped
        sleep 10
        local nginx_pods=$(kubectl get pods -n sample-apps -l app=nginx -o jsonpath='{.items[*].metadata.name}')
        if [ -n "$nginx_pods" ]; then
            print_pass "Nginx pods are running"
        else
            print_fail "No nginx pods found"
        fi
        
        return 0
    else
        print_fail "Sample nginx app deployment failed"
        return 1
    fi
}

test_nginx_metrics() {
    print_test "Checking if nginx metrics are available..."
    # Query Prometheus for any nginx_* series
    kubectl -n monitoring port-forward svc/prometheus 19091:9090 &>/dev/null &
    local pf_pid=$!
    sleep 3
    local count=$(curl -s "http://localhost:19091/api/v1/series?match[]=nginx_connections_accepted" 2>/dev/null | jq -r '.data | length' 2>/dev/null)
    kill $pf_pid 2>/dev/null || true
    if [ -n "$count" ] && [ "$count" -gt 0 ]; then
        print_pass "Nginx metrics are available in Prometheus"
        return 0
    else
        print_fail "Nginx metrics not available"
        return 1
    fi
}

test_argocd_login() {
    print_test "Testing ArgoCD login..."
    
    # Get password
    local password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
    
    if [ -n "$password" ]; then
        print_pass "ArgoCD admin password retrieved"
        print_info "Password: $password"
        return 0
    else
        print_fail "Could not retrieve ArgoCD admin password"
        return 1
    fi
}

# Main execution
echo "====================================="
echo "🔍 Kubernetes Environment Validation"
echo "====================================="
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    print_fail "jq is not installed. Please install it first: brew install jq"
    exit 1
fi

# Run tests
test_cluster_exists || true
test_kubectl_context || true
echo ""

echo "📦 ArgoCD Tests:"
test_argocd_namespace || true
test_argocd_pods || true
test_argocd_service || true
test_argocd_metrics || true
test_argocd_login || true
echo ""

echo "📊 Monitoring Tests:"
 test_monitoring_namespace || true
 test_prometheus_pod || true
 test_prometheus_service || true
 test_prometheus_targets || true
 test_grafana_pod || true
 test_grafana_service || true
 test_grafana_datasource || true
 echo ""

 echo "🚀 Sample Application Tests:"
 test_sample_app || true
 test_nginx_metrics || true
 echo ""

# Summary
echo "====================================="
echo "📋 Test Summary"
echo "====================================="
echo -e "${GREEN}Passed:${NC} $PASSED_TESTS"
echo -e "${RED}Failed:${NC} $FAILED_TESTS"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed. Please check the output above.${NC}"
    exit 1
fi
