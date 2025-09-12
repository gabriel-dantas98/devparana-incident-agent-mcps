#!/bin/bash

# Do not exit on errors; we want to show best-effort info

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e "${RED}[ERR ]${NC} $1"; }

# Basic checks
if ! command -v kubectl >/dev/null 2>&1; then
  print_err "kubectl not found. Install with: brew install kubectl"
  exit 1
fi

echo "====================================="
echo "🔗 Local Endpoint URLs"
echo "====================================="
echo ""

# cluster/context sanity
if ! kind get clusters 2>/dev/null | grep -q '^agent-cluster$'; then
  print_warn "Kind cluster 'agent-cluster' not found. URLs may not be reachable."
fi

if ! kubectl cluster-info --context kind-agent-cluster >/dev/null 2>&1; then
  print_warn "kubectl context 'kind-agent-cluster' not active."
fi

# Detect ingress
have_ingress=false
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  if kubectl get deploy ingress-nginx-controller -n ingress-nginx >/dev/null 2>&1; then
    have_ingress=true
  fi
fi

HOST_PORT=8080

if [ "$have_ingress" = true ]; then
  # Check /etc/hosts for localdev.me wildcard or service hosts
  if ! grep -E "(^|\s)localdev\.me(\s|$)" /etc/hosts >/dev/null 2>&1 \
     && ! grep -E "(^|\s)(argocd|backstage|grafana|prometheus)\.localdev\.me(\s|$)" /etc/hosts >/dev/null 2>&1; then
    print_warn "Adicione mapeamentos no /etc/hosts para localdev.me (exemplos abaixo)."
    echo "  127.0.0.1   localdev.me"
    echo "  127.0.0.1   argocd.localdev.me backstage.localdev.me grafana.localdev.me prometheus.localdev.me"
    echo ""
  fi

  echo "Ingress-based URLs (via localhost:${HOST_PORT}):"
  echo "  ArgoCD:     http://argocd.localdev.me:${HOST_PORT}"
  echo "  Backstage:  http://backstage.localdev.me:${HOST_PORT} (requires build)"
  echo "  Grafana:    http://grafana.localdev.me:${HOST_PORT}"
  echo "  Prometheus: http://prometheus.localdev.me:${HOST_PORT}"
else
  print_warn "Ingress not detected. You can use port-forward instead:"
  echo "  kubectl port-forward -n argocd svc/argocd-server 8080:80"
  echo "  kubectl port-forward -n backstage svc/backstage 7007:7007"
  echo "  kubectl port-forward -n monitoring svc/grafana 3000:3000"
  echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
fi

echo ""
echo "Done."
