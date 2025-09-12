
#!/usr/bin/env python

import os
import logging
import requests
from typing import Any, Dict, Optional
from dataclasses import dataclass
from langchain_core.tools import tool

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

logger.info("Initializing ArgoCD Tools")

@dataclass
class ArgoCDConfig:
    url: str
    token: str

config = ArgoCDConfig(
    url=os.environ.get("ARGOCD_URL", ""),
    token=os.environ.get("ARGOCD_TOKEN", "")
)

def make_argocd_request(endpoint: str, method: str = "GET", json: Optional[dict] = None, params: Optional[dict] = None) -> Any:
    if not config.url or not config.token:
        raise ValueError("ArgoCD configuration missing. Set ARGOCD_URL and ARGOCD_TOKEN.")
    url = f"{config.url.rstrip('/')}/api/v1/{endpoint.lstrip('/')}"
    headers = {"Authorization": f"Bearer {config.token}"}
    logger.debug(f"Requesting {method} {url} params={params} json={json}")
    resp = requests.request(method, url, headers=headers, params=params, json=json, timeout=30)
    resp.raise_for_status()
    return resp.json()

@tool(description="Lists all applications managed by ArgoCD, including name, status, project, namespace and sync information. Use to get an overview of the environment state and quickly identify applications with errors, outdated or out of compliance. Ideal for initial incident triage and impact analysis.")
async def list_applications() -> Dict[str, Any]:
    logger.info("Listing ArgoCD applications")
    data = make_argocd_request("applications")
    return {"applications": data.get("items", [])}

@tool(description="Gets detailed status of a specific ArgoCD application, including health, sync status, revision, error messages and recent conditions. Essential for incident diagnosis, deployment troubleshooting and regression analysis. Provides context for decision making without executing any change actions.")
async def get_application_status(app_name: str) -> Dict[str, Any]:
    logger.info(f"Getting status for application: {app_name}")
    data = make_argocd_request(f"applications/{app_name}")
    return {"status": data.get("status", {}), "metadata": data.get("metadata", {})}

@tool(description="Gets the most recent logs from pods associated with an ArgoCD application. Useful for failure analysis, incident debugging and root cause identification without direct cluster access. The returned logs are read-only and do not change system state. Optional parameters: number of lines, specific container.")
async def get_application_logs(app_name: str, container_name: str, lines: int = 100) -> Dict[str, Any]:
    logger.info(f"Getting logs for application: {app_name}")
    params = {"tailLines": lines, "container": container_name}

    log_content = get_pod_logs_stream(app_name, params)

    return {"logs": log_content}

@tool(description="Gets all recent events related to an ArgoCD application, including warnings, sync failures, health errors and Kubernetes events. Essential for understanding incident timeline, identifying causes and dependencies, and enriching resolver agent context. Does not execute any change actions.")
async def get_application_events(app_name: str) -> Dict[str, Any]:
    logger.info(f"Getting events for application: {app_name}")
    try:
        ev_data = make_argocd_request(f"applications/{app_name}/events")
        events = ev_data.get("items", [])
    except Exception as e:
        events = [{"error": str(e)}]
    return {"events": events}

def get_pod_logs_stream(app_name, params):
    url = f"{config.url.rstrip('/')}/api/v1/applications/{app_name}/logs"
    headers = {"Authorization": f"Bearer {config.token}"}
    with requests.get(url, headers=headers, params=params, stream=True, timeout=10) as resp:
        resp.raise_for_status()
        # Read only the first lines of the stream
        lines = []
        for line in resp.iter_lines():
            if line:
                lines.append(line.decode())
            if len(lines) >= params.get("tailLines", 100):
                break
        return "\n".join(lines)
