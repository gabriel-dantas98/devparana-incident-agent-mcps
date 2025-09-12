# Local Kubernetes Environment with Kind

This directory contains everything needed to set up a local Kubernetes environment with ArgoCD, Prometheus, and Grafana for testing and development.

## 🚀 Quick Start

```bash
# Configure /etc/hosts for localdev.me endpoints (one-time)
make setup-hosts

# Setup the entire environment
make setup

# Check status
make status

# Run validation tests
make validate

# Get admin passwords
make get-passwords
```

## 📋 Prerequisites

- Docker Desktop running
- Kind installed: `brew install kind`
- kubectl installed: `brew install kubectl`
- jq installed: `brew install jq` (for validation scripts)

## 🏗️ Architecture

```
┌──────────────────────────────────────────┐
│         Kind Kubernetes Cluster          │
├──────────────────────────────────────────┤
│                                          │
│  ┌─────────────┐    ┌──────────────┐    │
│  │   ArgoCD    │───▶│ Sample Apps  │    │
│  │  Namespace  │    │  Namespace   │    │
│  └─────────────┘    └──────────────┘    │
│         │                   │            │
│         ▼                   ▼            │
│  ┌──────────────────────────────────┐   │
│  │      Monitoring Namespace        │   │
│  │  ┌────────────┐  ┌────────────┐  │   │
│  │  │ Prometheus │──│  Grafana   │  │   │
│  │  └────────────┘  └────────────┘  │   │
│  └──────────────────────────────────┘   │
│                                          │
└──────────────────────────────────────────┘
```

## 📁 Directory Structure

```
cluster/
├── Makefile                 # Convenient commands
├── kind-config.yaml         # Kind cluster configuration
├── resources/
│   ├── argocd/             # ArgoCD manifests
│   ├── prometheus/         # Prometheus configuration
│   ├── grafana/            # Grafana configuration
│   ├── langfuse/           # Langfuse Observability (app + Postgres)
│   └── sample-apps/        # Sample applications
└── scripts/
    ├── setup.sh            # Setup script
    ├── teardown.sh         # Cleanup script
    ├── validate.sh         # Validation tests
    └── check-metrics.sh    # Metrics validation
```

## 🛠️ Available Commands

### Makefile Commands

| Command | Description |
|---------|-------------|
| `make setup` | Create cluster and install all components |
| `make teardown` | Delete cluster and cleanup |
| `make status` | Check status of all components |
| `make validate` | Run validation tests |
| `make deploy-sample` | Deploy sample nginx application |
| `make clean-sample` | Remove sample applications |
| `make get-passwords` | Get admin passwords |
| `make port-forward` | Start port forwarding for all services |
| `make logs-argocd` | Show ArgoCD logs |
| `make logs-prometheus` | Show Prometheus logs |
| `make logs-grafana` | Show Grafana logs |

## 🌐 Access URLs

After running `make setup`, services are available at:

Note: Access via Ingress on port 8080 using `localdev.me` hosts (see `scripts/get-urls.sh`).

| Service | URL | Default Credentials |
|---------|-----|---------------------|
| ArgoCD | http://localhost:8080 | admin / (see below) |
| Grafana | http://localhost:3000 | admin / admin |
| Prometheus | http://localhost:9090 | No auth required |
| Langfuse | http://localhost:8080 (host: langfuse.localdev.me) | No auth by default (local) |

### Getting ArgoCD Password

```bash
make get-passwords
# or
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## 🧪 Validation

The validation script checks:

- ✅ Cluster existence and connectivity
- ✅ All pods are running
- ✅ Services have endpoints
- ✅ Metrics are being exposed
- ✅ Prometheus is scraping targets
- ✅ Grafana datasources are configured
- ✅ Sample app deployment and metrics

Run validation:

```bash
make validate
```

Check metrics collection:

```bash
./scripts/check-metrics.sh
```

## 📊 Monitoring

### Prometheus Targets

Prometheus is configured to scrape:

- ArgoCD metrics (port 8082, 8083, 8084)
- Kubernetes pods with Prometheus annotations
- Kubernetes nodes
- Sample nginx application (when deployed)

### Grafana Dashboards

Pre-configured dashboards:

- ArgoCD Overview - Application health, sync status, operations

### Adding Custom Metrics

To add Prometheus scraping to your pods:

```yaml
metadata:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
```

## 🚢 Sample Application

Deploy the sample nginx app to test the environment:

```bash
# Deploy sample app
make deploy-sample

# Check metrics
./scripts/check-metrics.sh

# Clean up
make clean-sample
```

The sample app includes:

- 3 nginx replicas
- Prometheus metrics exporter
- Health checks
- Resource limits

## 🔧 Troubleshooting

### Cluster won't start

```bash
# Check Docker is running
docker ps

# Delete existing cluster
kind delete cluster --name agent-cluster

# Try setup again
make setup
```

### Pods not starting

```bash
# Check pod status
kubectl get pods -A

# Check pod logs
kubectl logs -n <namespace> <pod-name>

# Describe pod
kubectl describe pod -n <namespace> <pod-name>
```

### Port forwarding issues

```bash
# Kill existing port forwards
pkill -f "port-forward"

# Restart port forwarding
make port-forward
```

### Metrics not showing

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Open http://localhost:9090/targets

# Check service discovery
kubectl get endpoints -A
```

## 🧹 Cleanup

To completely remove the environment:

```bash
make teardown
```

This will delete the Kind cluster and all associated resources.

## 📝 Notes

- The cluster uses NodePort services for external access
- All data is ephemeral (uses emptyDir volumes)
- Suitable for development and testing only
- Resource limits are set for local development

## 🔗 Integration with Agent

This environment is designed to work with the LangGraph agent in the parent directory. The agent can:

- Query ArgoCD for application status
- Retrieve metrics from Prometheus
- Create and manage applications
- Monitor deployment health

## 📚 Additional Resources

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)

## ♻️ Idempotency

The `make setup` script is idempotent. You can run it multiple times, and it will:

- Reuse the existing `agent-cluster` if present
- Ensure the local Docker registry is running and connected
- Apply Kubernetes resources using `kubectl apply` safely
- Wait for components (ArgoCD, ingress-nginx, Prometheus, Grafana) to be available
- Gracefully handle the ArgoCD admin password if it has already been rotated
