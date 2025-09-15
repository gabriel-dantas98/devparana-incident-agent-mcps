.PHONY: all setup teardown status validate deploy-sample clean-sample logs help get-urls registry-test update-discord-bot logs-discord-bot

# Variables
CLUSTER_NAME = agent-cluster
ARGOCD_NS = argocd
MONITORING_NS = monitoring
SAMPLE_NS = apps

# Default target
all: help

## help: Show this help message
help:
	@echo "Available commands:"
	@echo ""
	@grep -E '^##' Makefile | sed 's/## /  /'
	@echo ""

## setup-hosts: Add localdev.me hostnames to /etc/hosts (requires sudo)
setup-hosts:
	@chmod +x scripts/configure-hosts.sh
	@./scripts/configure-hosts.sh

## setup: Create Kind cluster and install all components
setup:
	@chmod +x scripts/setup.sh
	@./scripts/setup.sh

## teardown: Delete Kind cluster and cleanup
teardown:
	@chmod +x scripts/teardown.sh
	@./scripts/teardown.sh

## status: Check status of all components
status:
	@echo "📊 Checking cluster status..."
	@kubectl cluster-info --context kind-$(CLUSTER_NAME) 2>/dev/null || echo "❌ Cluster not found"
	@echo ""
	@echo "ArgoCD Status:"
	@kubectl get pods -n $(ARGOCD_NS) 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "Monitoring Status:"
	@kubectl get pods -n $(MONITORING_NS) 2>/dev/null || echo "  Not installed"
	@echo ""
	@echo "Sample Apps:"
	@kubectl get pods -n $(SAMPLE_NS) 2>/dev/null || echo "  No sample apps deployed"

## validate: Run validation tests
validate:
	@chmod +x scripts/validate.sh
	@./scripts/validate.sh

## get-urls: Print local access URLs (Ingress or port-forward hints)
get-urls:
	@chmod +x scripts/get-urls.sh
	@./scripts/get-urls.sh

## registry-test: Build local image, push to local registry, deploy and verify
registry-test:
	@chmod +x scripts/registry-test.sh
	@./scripts/registry-test.sh

## deploy-sample: Deploy sample nginx application
deploy-sample:
	@echo "🚀 Deploying sample nginx application..."
	@kubectl create namespace $(SAMPLE_NS) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl apply -f resources/sample-apps/

## clean-sample: Remove sample applications
clean-sample:
	@echo "🧹 Removing sample applications..."
	@kubectl delete namespace $(SAMPLE_NS) --ignore-not-found=true

## logs-argocd: Show ArgoCD logs
logs-argocd:
	@kubectl logs -n $(ARGOCD_NS) -l app.kubernetes.io/name=argocd-server --tail=50 -f

## logs-prometheus: Show Prometheus logs
logs-prometheus:
	@kubectl logs -n $(MONITORING_NS) -l app=prometheus --tail=50 -f

## logs-grafana: Show Grafana logs
logs-grafana:
	@kubectl logs -n $(MONITORING_NS) -l app=grafana --tail=50 -f

## port-forward: Start port forwarding for all services
port-forward:
	@echo "🔌 Starting port forwarding..."
	@echo "  ArgoCD: http://localhost:8080"
	@echo "  Backstage: http://localhost:7007"
	@echo "  Grafana: http://localhost:3000"
	@echo "  Prometheus: http://localhost:9090"
	@echo ""
	@echo "Press Ctrl+C to stop..."
	@kubectl port-forward svc/argocd-server -n $(ARGOCD_NS) 8080:80 &
	@kubectl port-forward svc/backstage -n backstage 7007:7007 &
	@kubectl port-forward svc/grafana -n $(MONITORING_NS) 3000:3000 &
	@kubectl port-forward svc/prometheus -n $(MONITORING_NS) 9090:9090 &
	@wait

## get-passwords: Get admin passwords for services
get-passwords:
	@echo "🔐 Admin Passwords:"
	@echo ""
	@echo "ArgoCD:"
	@echo "  Username: admin"
	@echo -n "  Password: "
	@kubectl -n $(ARGOCD_NS) get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "Not available"
	@echo ""
	@echo ""
	@echo "Grafana:"
	@echo "  Username: admin"
	@echo "  Password: admin"

## restart-argocd: Restart ArgoCD components
restart-argocd:
	@echo "🔄 Restarting ArgoCD..."
	@kubectl rollout restart deployment -n $(ARGOCD_NS)
	@kubectl rollout status deployment -n $(ARGOCD_NS)

## restart-monitoring: Restart monitoring components
restart-monitoring:
	@echo "🔄 Restarting monitoring stack..."
	@kubectl rollout restart deployment -n $(MONITORING_NS)
	@kubectl rollout status deployment -n $(MONITORING_NS)

## build-backstage: Build and deploy Backstage
build-backstage:
	@echo "🎭 Building and deploying Backstage..."
	@chmod +x scripts/build-backstage.sh
	@./scripts/build-backstage.sh

## restart-backstage: Restart Backstage components
restart-backstage:
	@echo "🔄 Restarting Backstage..."
	@kubectl rollout restart deployment -n backstage
	@kubectl rollout status deployment -n backstage

## logs-backstage: Show Backstage logs
logs-backstage:
	@kubectl logs -n backstage -l app=backstage --tail=50 -f

## update-discord-bot: Update Discord webhook proxy image
update-discord-bot:
	@chmod +x scripts/update-discord-bot.sh
	@./scripts/update-discord-bot.sh

## logs-discord-bot: Show Discord webhook proxy logs
logs-discord-bot:
	@kubectl logs -n $(MONITORING_NS) -l app=discord-webhook-proxy --tail=50 -f
