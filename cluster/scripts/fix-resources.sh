#!/bin/bash

set -e

echo "🔧 Fixing Resource Issues for Kind Cluster..."
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}[INFO]${NC} Current Docker resource usage:"
docker system df
echo ""

echo -e "${YELLOW}[INFO]${NC} Number of running containers: $(docker ps -q | wc -l)"
echo ""

# Step 1: Delete existing Kind cluster
echo -e "${BLUE}[STEP 1]${NC} Cleaning up existing Kind cluster..."
kind delete cluster --name agent-cluster 2>/dev/null || true
echo "✅ Cluster cleaned"

# Step 2: Stop unnecessary containers (preserving important ones)
echo -e "${BLUE}[STEP 2]${NC} Stopping unnecessary containers..."
echo "Current running containers:"
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"
echo ""

read -p "Do you want to stop all non-essential containers? (y/n): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Stop all containers except postgres and killgrave
    docker ps -q | while read container; do
        name=$(docker inspect --format '{{.Name}}' $container | sed 's/\///')
        if [[ ! "$name" =~ (postgres|killgrave) ]]; then
            echo "Stopping container: $name"
            docker stop $container 2>/dev/null || true
        else
            echo "Preserving: $name"
        fi
    done
fi

# Step 3: Clean Docker resources
echo ""
echo -e "${BLUE}[STEP 3]${NC} Cleaning Docker resources..."
docker system prune -f --volumes
echo "✅ Docker resources cleaned"

# Step 4: Check available resources
echo ""
echo -e "${BLUE}[STEP 4]${NC} Available system resources:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Memory: $(vm_stat | grep 'Pages free' | awk '{print $3}' | sed 's/\.//') pages free"
    echo "CPU cores: $(sysctl -n hw.ncpu)"
fi

echo ""
echo -e "${GREEN}✅ Resource cleanup completed!${NC}"
echo ""
echo "Next steps:"
echo "1. Run: ./scripts/setup.sh"
echo "2. This will create a local cluster with ArgoCD, Prometheus and Grafana"
