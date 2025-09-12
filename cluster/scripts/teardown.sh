#!/bin/bash

set -e

echo "🗑️  Tearing down local Kubernetes environment..."

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "❌ Kind is not installed."
    exit 1
fi

# Check if the cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^agent-cluster$"; then
    echo "⚠️  Cluster 'agent-cluster' does not exist."
    exit 0
fi

# Delete the cluster
echo "🔥 Deleting Kind cluster..."
kind delete cluster --name agent-cluster

echo "✅ Teardown completed successfully!"
