#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$CLUSTER_DIR/resources"
REG_NAME="kind-registry"
REG_PORT="5000"

echo "🚀 Setting up local Kubernetes environment with Kind..."

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ Kind is not installed. Please install it first:"
    echo "   brew install kind"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl is not installed. Please install it first:"
    echo "   brew install kubectl"
    exit 1
fi

# Check if docker is installed (required for local registry and kind)
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed or not in PATH. Please install/start Docker Desktop."
    exit 1
fi

# Ensure cluster exists (idempotent)
if kind get clusters 2>/dev/null | grep -q "^agent-cluster$"; then
    echo "ℹ️  Reusing existing Kind cluster 'agent-cluster'"
else
    echo "📦 Creating Kind cluster..."
    kind create cluster --config "$CLUSTER_DIR/kind-config.yaml"
fi

# Ensure kubectl context is set to our cluster
kubectl config use-context "kind-agent-cluster" >/dev/null 2>&1 || true

# Ensure local registry (for local images)
echo "🛢️  Ensuring local Docker registry ($REG_NAME) at 127.0.0.1:5001..."
REG_RUNNING=$(docker inspect -f '{{.State.Running}}' "$REG_NAME" 2>/dev/null || true)
if [ "$REG_RUNNING" != "true" ]; then
    if docker ps -a --format '{{.Names}}' | grep -q "^$REG_NAME$"; then
        docker start "$REG_NAME" >/dev/null
    else
        docker run -d --restart=always -p "127.0.0.1:5001:${REG_PORT}" --name "$REG_NAME" registry:2 >/dev/null
    fi
fi

# Connect registry container to kind network so mirror "kind-registry:5000" resolves inside cluster
docker network connect kind "$REG_NAME" 2>/dev/null || true

# Install ArgoCD via local kustomization (ensures NodePort and metrics)
echo "🔄 Installing ArgoCD (kustomize)..."
kubectl apply -k "$RESOURCES_DIR/argocd"

# Ensure ArgoCD runs with HTTP (insecure) and ADMIN auth enabled (no anonymous)
echo "🔧 Enforcing ArgoCD HTTP mode with admin auth..."
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge -p '{"data":{"server.insecure":"true","server.disable.auth":"false"}}' >/dev/null || true
kubectl -n argocd patch configmap argocd-cm --type merge -p '{"data":{"users.anonymous.enabled":"false","admin.enabled":"true"}}' >/dev/null || true
# Publish external URL used in tokens and UI
aRG_URL_PATCH='{"data":{"url":"http://argocd.localdev.me:8080"}}'
kubectl -n argocd patch configmap argocd-server-config --type merge -p "$aRG_URL_PATCH" >/dev/null || true

# Restart ArgoCD server to pick up configmap changes
echo "🔁 Restarting ArgoCD server..."
kubectl rollout restart deployment/argocd-server -n argocd >/dev/null || true

# Install ingress-nginx for Kind and apply ingress resources
echo "🌐 Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Bootstrap ArgoCD Application for sample-apps
echo "🧩 Bootstrapping ArgoCD Application for sample-apps..."
REPO_ROOT="$(cd "$CLUSTER_DIR/.." && pwd)"
REPO_URL="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
if [ -n "$REPO_URL" ]; then
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO_URL}
    targetRevision: HEAD
    path: cluster/resources/sample-apps
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
EOF
else
  echo "⚠️  Could not determine git remote URL; skipping Application bootstrap."
fi

# Install Prometheus
echo "📊 Installing Prometheus..."
kubectl apply -f "$RESOURCES_DIR/prometheus/namespace.yaml"
kubectl apply -f "$RESOURCES_DIR/prometheus/prometheus-rbac.yaml"
kubectl apply -f "$RESOURCES_DIR/prometheus/prometheus-config.yaml"
# Ensure kube-state-metrics is present
kubectl apply -f "$RESOURCES_DIR/prometheus/kube-state-metrics.yaml"
kubectl apply -f "$RESOURCES_DIR/prometheus/prometheus-deployment.yaml"

# Install Grafana
echo "📈 Installing Grafana..."
kubectl apply -f "$RESOURCES_DIR/grafana/grafana-config.yaml"
kubectl apply -f "$RESOURCES_DIR/grafana/argocd-dashboard.yaml"
kubectl apply -f "$RESOURCES_DIR/grafana/grafana-deployment.yaml"

# Install Backstage (only resources, build-backstage.sh handles image build/deploy)
echo "🎭 Installing Backstage resources..."
kubectl apply -f "$RESOURCES_DIR/backstage/backstage-deployment.yaml"

# Apply ingress routes
echo "🧭 Applying ingress routes..."
kubectl apply -k "$RESOURCES_DIR/ingress"

# Basic ingress validation (HTTP status codes)
echo "🔎 Validating ingress endpoints..."
set +e
ARG="--resolve"
curl -sS -o /dev/null -w "ArgoCD:      %{http_code} %{url_effective}\n" $ARG argocd.localdev.me:8080:127.0.0.1 http://argocd.localdev.me:8080/ || true
curl -sS -o /dev/null -w "Backstage:   %{http_code} %{url_effective}\n" $ARG backstage.localdev.me:8080:127.0.0.1 http://backstage.localdev.me:8080/ || true
curl -sS -o /dev/null -w "Grafana:     %{http_code} %{url_effective}\n" $ARG grafana.localdev.me:8080:127.0.0.1 http://grafana.localdev.me:8080/ || true
curl -sS -o /dev/null -w "Prometheus:  %{http_code} %{url_effective}\n" $ARG prometheus.localdev.me:8080:127.0.0.1 http://prometheus.localdev.me:8080/ || true
set -e

# --- Generate ArgoCD API token and write env files ---
echo "🔐 Generating ArgoCD API token and writing env files..."
ARGOCD_HOST="argocd.localdev.me"
ARGOCD_PORT="8080"
ARGOCD_URL="http://${ARGOCD_HOST}:${ARGOCD_PORT}"
RESOLVE_ARGS=(--resolve "${ARGOCD_HOST}:${ARGOCD_PORT}:127.0.0.1")

# Wait for initial admin password (admin must be enabled)
ATTEMPTS=30
SLEEP_SECONDS=2
ARGOCD_PASSWORD=""
for i in $(seq 1 $ATTEMPTS); do
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
  if [ -n "${ARGOCD_PASSWORD:-}" ]; then
    break
  fi
  sleep "$SLEEP_SECONDS"
done

ARGOCD_TOKEN=""
if [ -n "${ARGOCD_PASSWORD:-}" ]; then
  for i in $(seq 1 $ATTEMPTS); do
    SESSION_JSON=$(curl -sS "${RESOLVE_ARGS[@]}" -H "Host: ${ARGOCD_HOST}" -H "Content-Type: application/json" -X POST \
      -d "{\"username\":\"admin\",\"password\":\"${ARGOCD_PASSWORD}\"}" \
      "${ARGOCD_URL}/api/v1/session" || true)
    if command -v jq >/dev/null 2>&1; then
      ARGOCD_TOKEN=$(echo "$SESSION_JSON" | jq -r '.token // empty')
    else
      ARGOCD_TOKEN=$(python3 -c 'import sys,json; import os; data=sys.stdin.read();\
obj=json.loads(data) if data.strip() else {}; print(obj.get("token",""))' <<< "$SESSION_JSON" 2>/dev/null || echo "")
    fi
    if [ -n "${ARGOCD_TOKEN:-}" ]; then
      break
    fi
    sleep "$SLEEP_SECONDS"
  done
else
  echo "⚠️  Admin password not found; token generation skipped."
fi

# Write env files at repo root
ENV_EXPORT_FILE="$REPO_ROOT/.argocd.env"
DOTENV_FILE="$REPO_ROOT/.env.argocd"
{
  echo "export ARGOCD_URL=${ARGOCD_URL}"
  echo "export ARGOCD_TOKEN=${ARGOCD_TOKEN}"
} > "$ENV_EXPORT_FILE"
{
  echo "ARGOCD_URL=${ARGOCD_URL}"
  echo "ARGOCD_TOKEN=${ARGOCD_TOKEN}"
} > "$DOTENV_FILE"

echo "✅ Wrote ArgoCD env to:"
echo "  $ENV_EXPORT_FILE"
echo "  $DOTENV_FILE"

# Get ArgoCD admin password (may be absent if it was changed already)
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || true)
if [ -z "${ARGOCD_PASSWORD:-}" ]; then
  ARGOCD_PASSWORD="(not available - password may have been changed)"
fi

echo ""
echo "✅ Setup completed successfully!"
echo ""
echo "📝 Access Information:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "ArgoCD:"
echo "  URL: http://argocd.localdev.me:8080 (via Ingress)"
echo "  Username: admin"
echo "  Password: $ARGOCD_PASSWORD"
echo "  Env file: $ENV_EXPORT_FILE (run: source $ENV_EXPORT_FILE)"
echo ""
echo "Backstage:"
echo "  URL: http://backstage.localdev.me:8080 (build required)"
echo "  Build: ./scripts/build-backstage.sh"
echo ""
echo "Grafana:"
echo "  URL: http://grafana.localdev.me:8080"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Prometheus:"
echo "  URL: http://prometheus.localdev.me:8080"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "💡 To access services, run:"
echo "  make port-forward"
echo ""
echo "Or manually:"
echo "  Ingress URLs (requires kind extraPortMappings 8080/8443):"
echo "    ArgoCD:     http://argocd.localdev.me:8080"
echo "    Grafana:    http://grafana.localdev.me:8080"
echo "    Prometheus: http://prometheus.localdev.me:8080"
