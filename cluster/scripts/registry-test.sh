#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLUSTER_DIR="$(dirname "$SCRIPT_DIR")"
BACKSTAGE_DIR="$CLUSTER_DIR/resources/backstage/packages/backend"

REG_NAME='kind-registry'
REG_PORT='5000'

echo "[1/7] Ensuring local registry ${REG_NAME}..."
running="$(docker inspect -f '{{.State.Running}}' ${REG_NAME} 2>/dev/null || true)"
if [ "$running" != 'true' ]; then
  docker run -d --restart=always -p "127.0.0.1:5001:${REG_PORT}" --name "${REG_NAME}" registry:2
fi

echo "[2/7] Recreating kind cluster with registry mirror..."
kind delete cluster --name agent-cluster || true
kind create cluster --config "$CLUSTER_DIR/kind-config.yaml"

echo "[3/7] Connecting registry to cluster network..."
docker network connect "kind" "${REG_NAME}" 2>/dev/null || true

echo "[4/7] Building image..."
IMAGE="localhost:5001/backstage-backend:dev"
ARTIFACT="$CLUSTER_DIR/resources/backstage/packages/backend/dist/bundle.tar.gz"
if [ -f "$BACKSTAGE_DIR/Dockerfile" ] && [ -f "$ARTIFACT" ]; then
  echo "  - Using Backstage Dockerfile (artifacts present)"
  docker build -t "$IMAGE" "$BACKSTAGE_DIR"
else
  echo "  - Backstage artifacts not found; building minimal test image instead"
  TMPDIR=$(mktemp -d)
  cat >"$TMPDIR/Dockerfile" <<'EOF'
FROM alpine:3.19
RUN adduser -D app
USER app
CMD ["sh", "-c", "echo ok && sleep 3600"]
EOF
  docker build -t "$IMAGE" "$TMPDIR"
fi

echo "[5/7] Pushing to local registry..."
docker push "$IMAGE"

echo "[6/7] Deploying to kind..."
kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backstage-backend
  namespace: backstage
spec:
  replicas: 1
  selector:
    matchLabels: { app: backstage-backend }
  template:
    metadata:
      labels: { app: backstage-backend }
    spec:
      containers:
        - name: backend
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 7007
          readinessProbe:
            httpGet: { path: /healthcheck, port: 7007 }
            initialDelaySeconds: 10
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: backstage-backend
  namespace: backstage
spec:
  selector: { app: backstage-backend }
  ports:
    - port: 7007
      targetPort: 7007
      name: http
EOF

echo "[7/7] Waiting for pod and checking for ImagePullBackOff..."
kubectl wait --for=condition=Available deploy/backstage-backend -n backstage --timeout=180s || true
kubectl get pods -n backstage -o wide
echo "\nEvents:"
kubectl get events -n backstage --sort-by=.lastTimestamp | tail -n 20

status=$(kubectl get pods -n backstage -l app=backstage-backend -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || true)
if echo "$status" | grep -q "ImagePullBackOff\|ErrImagePull"; then
  echo "❌ Image pull failed: $status"; exit 1
fi

echo "✅ Deployed without ImagePullBackOff using local registry mirror."
