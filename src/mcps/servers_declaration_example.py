import os
from langchain_mcp_adapters.client import MultiServerMCPClient

prometheusMCPClient = {
            "command": "docker",
            "transport": "stdio",
            "args": [
                "run",
                "--rm",
                "-i",
                "-e",
                "PROMETHEUS_URL",
                "prometheus-mcp-server",
            ],
            "env": {
                "PROMETHEUS_URL": "https://thanos-query.apps.shared-prd.habitat.zone"
            }
    }

argocdMCPClient = { 
            "command": "npx",
            "transport": "stdio",
            "args": [
              "argocd-mcp@latest",
              "stdio"
                ],
            "env": {
                "ARGOCD_TOKEN": os.getenv("ARGOCD_TOKEN"),
                "ARGOCD_URL": os.getenv("ARGOCD_URL")
            }
        }

backstageMCPClient = {
            "command": "docker",
            "transport": "stdio",
            "args": [
                "run", 
                "--rm", 
                "-i", 
                "-e", 
                "BACKSTAGE_BASE_URL", 
                "backstage-mcp-server"
                ],
            "env": {
                "BACKSTAGE_BASE_URL": os.getenv("BACKSTAGE_BASE_URL")
            }
        }

MCP_CLIENTS = MultiServerMCPClient({
    "prometheus": prometheusMCPClient,
    "argocd": argocdMCPClient,
    "software-catalog": backstageMCPClient
})
