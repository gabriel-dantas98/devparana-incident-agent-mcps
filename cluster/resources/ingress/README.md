# Ingress hosts

Expose services via `localdev.me` on host port 8080 (see `kind-config.yaml`).

- argocd.localdev.me -> `argocd` service (80)
- grafana.localdev.me -> `grafana` service (3000)
- prometheus.localdev.me -> `prometheus` service (9090)
