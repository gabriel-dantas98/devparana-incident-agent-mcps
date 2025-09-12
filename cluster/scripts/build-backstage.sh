#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(dirname "$SCRIPT_DIR")"
BACKSTAGE_DIR="$CLUSTER_DIR/resources/backstage"

echo "🏗️  Building and deploying Backstage..."

# Check if backstage directory exists
if [ ! -d "$BACKSTAGE_DIR" ]; then
    echo "❌ Backstage directory not found at: $BACKSTAGE_DIR"
    exit 1
fi

# Change to backstage directory
cd "$BACKSTAGE_DIR"

# Yarn check removed - using simplified Docker build

# Check if docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker Desktop."
    exit 1
fi                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     

echo "🔨 Using Node.js 20 by nvm..."
# Load nvm and use Node 20
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm use 20 || echo "⚠️  nvm not available, using current Node version"

echo "🔨 Installing dependencies..."
yarn install 

echo "🔨 Building Backstage..."
yarn tsc 
yarn build:all

echo "🔨 Building Backstage image..."
yarn build-image

echo "📤 Loading image into Kind cluster..."
kind load docker-image backstage:latest --name agent-cluster

echo "☸️  Checking Kubernetes connection..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Cannot connect to Kubernetes cluster. Please ensure cluster is running."
    exit 1
fi

echo "🚀 Applying Kubernetes resources..."
kubectl apply -f "$CLUSTER_DIR/resources/backstage/backstage-deployment.yaml"

echo "⏳ Waiting for deployment to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/backstage -n backstage

echo "🔄 Restarting deployment to use new image..."
kubectl rollout restart deployment/backstage -n backstage

echo "⏳ Waiting for rollout to complete..."
kubectl rollout status deployment/backstage -n backstage --timeout=300s

echo "✅ Backstage build and deployment completed successfully!"
echo ""
echo "📝 Access Information:"
echo "  URL: http://backstage.localdev.me:8080"
echo "  Or via port-forward: kubectl port-forward svc/backstage -n backstage 7007:7007"
echo ""
echo "📊 Pod Status:"
kubectl get pods -n backstage -l app=backstage
