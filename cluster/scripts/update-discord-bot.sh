#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="discord-webhook-proxy"
IMAGE_TAG="latest"
CLUSTER_NAME="agent-cluster"
NAMESPACE="monitoring"
DEPLOYMENT_NAME="discord-webhook-proxy"
DOCKERFILE_PATH="/Users/gabriel.dantas/git/insight/hello-langrafo/cluster/resources/prometheus"

echo -e "${BLUE}🤖 Updating Discord Webhook Proxy...${NC}"

# Check if kind cluster exists
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${RED}❌ Kind cluster '${CLUSTER_NAME}' not found${NC}"
    echo -e "${YELLOW}💡 Run 'make setup' first to create the cluster${NC}"
    exit 1
fi

# Check if kubectl context is set correctly
if ! kubectl config current-context | grep -q "kind-${CLUSTER_NAME}"; then
    echo -e "${YELLOW}⚠️  Setting kubectl context to kind cluster...${NC}"
    kubectl config use-context "kind-${CLUSTER_NAME}"
fi

# Step 1: Build Docker image
echo -e "${BLUE}🔨 Building Docker image...${NC}"
cd "${DOCKERFILE_PATH}"
if docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .; then
    echo -e "${GREEN}✅ Docker image built successfully${NC}"
else
    echo -e "${RED}❌ Failed to build Docker image${NC}"
    exit 1
fi

# Step 2: Load image into kind cluster
echo -e "${BLUE}📦 Loading image into kind cluster...${NC}"
if kind load docker-image "${IMAGE_NAME}:${IMAGE_TAG}" --name "${CLUSTER_NAME}"; then
    echo -e "${GREEN}✅ Image loaded into kind cluster${NC}"
else
    echo -e "${RED}❌ Failed to load image into cluster${NC}"
    exit 1
fi

# Step 3: Check if deployment exists
if ! kubectl -n "${NAMESPACE}" get deployment "${DEPLOYMENT_NAME}" &>/dev/null; then
    echo -e "${YELLOW}⚠️  Deployment not found, creating it...${NC}"
    kubectl -n "${NAMESPACE}" apply -f discord-webhook-proxy.yaml
fi

# Step 4: Restart deployment to use new image
echo -e "${BLUE}🔄 Restarting deployment...${NC}"
if kubectl -n "${NAMESPACE}" rollout restart deployment "${DEPLOYMENT_NAME}"; then
    echo -e "${GREEN}✅ Deployment restarted${NC}"
else
    echo -e "${RED}❌ Failed to restart deployment${NC}"
    exit 1
fi

# Step 5: Wait for rollout to complete
echo -e "${BLUE}⏳ Waiting for rollout to complete...${NC}"
if kubectl -n "${NAMESPACE}" rollout status deployment "${DEPLOYMENT_NAME}" --timeout=120s; then
    echo -e "${GREEN}✅ Rollout completed successfully${NC}"
else
    echo -e "${RED}❌ Rollout failed or timed out${NC}"
    exit 1
fi

# Step 6: Verify pod is running
echo -e "${BLUE}🔍 Verifying pod status...${NC}"
if kubectl -n "${NAMESPACE}" get pods -l app="${DEPLOYMENT_NAME}" --field-selector=status.phase=Running | grep -q "${DEPLOYMENT_NAME}"; then
    echo -e "${GREEN}✅ Pod is running successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Pod might still be starting up. Check with:${NC}"
    echo "kubectl -n ${NAMESPACE} get pods -l app=${DEPLOYMENT_NAME}"
fi

# Step 7: Show logs (last 10 lines)
echo -e "${BLUE}📋 Recent logs:${NC}"
kubectl -n "${NAMESPACE}" logs -l app="${DEPLOYMENT_NAME}" --tail=5 || echo -e "${YELLOW}⚠️  Could not retrieve logs (pod might be starting)${NC}"

echo ""
echo -e "${GREEN}🎉 Discord webhook proxy updated successfully!${NC}"
echo ""
echo -e "${BLUE}📊 Useful commands:${NC}"
echo "  View logs:    kubectl -n ${NAMESPACE} logs -f -l app=${DEPLOYMENT_NAME}"
echo "  Check status: kubectl -n ${NAMESPACE} get pods -l app=${DEPLOYMENT_NAME}"
echo "  Test webhook: kubectl -n ${NAMESPACE} port-forward svc/${DEPLOYMENT_NAME} 8081:8080"
echo ""
