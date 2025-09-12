#!/usr/bin/env python

import os
import logging
import subprocess
import json
from typing import Any, Dict, List, Optional
from langchain_core.tools import tool
from kubernetes import client, config
from kubernetes.client.rest import ApiException

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

logger.info("Initializing Kubernetes Tools")

# Initialize Kubernetes client
try:
    # Try to load in-cluster config first
    config.load_incluster_config()
    logger.info("Using in-cluster Kubernetes configuration")
except:
    try:
        # Fall back to kubeconfig
        config.load_kube_config(context="kind-agent-cluster")
        logger.info("Using kubeconfig for kind-agent-cluster context")
    except Exception as e:
        logger.warning(f"Could not load Kubernetes config: {e}")

# Initialize API clients
v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()

@tool(description="Lists all pods in a namespace with their status, restart count, and resource usage. Essential for incident triage and identifying problematic pods. Use 'all' for namespace to get cluster-wide view.")
async def list_pods(namespace: str = "default") -> Dict[str, Any]:
    """List pods in a namespace or all namespaces."""
    logger.info(f"Listing pods in namespace: {namespace}")
    try:
        if namespace == "all":
            pods = v1.list_pod_for_all_namespaces(watch=False)
        else:
            pods = v1.list_namespaced_pod(namespace, watch=False)
        
        pod_list = []
        for pod in pods.items:
            pod_info = {
                "name": pod.metadata.name,
                "namespace": pod.metadata.namespace,
                "status": pod.status.phase,
                "ready": f"{sum(1 for c in pod.status.container_statuses or [] if c.ready)}/{len(pod.spec.containers)}",
                "restarts": sum(c.restart_count for c in pod.status.container_statuses or []),
                "age": str(pod.metadata.creation_timestamp),
                "node": pod.spec.node_name
            }
            pod_list.append(pod_info)
        
        return {"pods": pod_list, "count": len(pod_list)}
    except ApiException as e:
        logger.error(f"Error listing pods: {e}")
        return {"error": str(e), "pods": []}

@tool(description="Gets detailed information about a specific pod including containers, volumes, events, and conditions. Critical for debugging pod failures and resource issues.")
async def describe_pod(pod_name: str, namespace: str = "default") -> Dict[str, Any]:
    """Get detailed pod information."""
    logger.info(f"Describing pod {pod_name} in namespace {namespace}")
    try:
        pod = v1.read_namespaced_pod(pod_name, namespace)
        
        # Get pod events
        events = v1.list_namespaced_event(
            namespace,
            field_selector=f"involvedObject.name={pod_name}"
        )
        
        pod_details = {
            "name": pod.metadata.name,
            "namespace": pod.metadata.namespace,
            "status": {
                "phase": pod.status.phase,
                "conditions": [
                    {
                        "type": c.type,
                        "status": c.status,
                        "reason": c.reason,
                        "message": c.message
                    } for c in pod.status.conditions or []
                ],
                "container_statuses": [
                    {
                        "name": c.name,
                        "ready": c.ready,
                        "restart_count": c.restart_count,
                        "state": {
                            "running": c.state.running is not None,
                            "terminated": c.state.terminated.to_dict() if c.state.terminated else None,
                            "waiting": c.state.waiting.to_dict() if c.state.waiting else None
                        }
                    } for c in pod.status.container_statuses or []
                ]
            },
            "spec": {
                "node_name": pod.spec.node_name,
                "containers": [
                    {
                        "name": c.name,
                        "image": c.image,
                        "resources": c.resources.to_dict() if c.resources else {}
                    } for c in pod.spec.containers
                ]
            },
            "events": [
                {
                    "type": e.type,
                    "reason": e.reason,
                    "message": e.message,
                    "count": e.count,
                    "last_timestamp": str(e.last_timestamp)
                } for e in events.items
            ]
        }
        
        return pod_details
    except ApiException as e:
        logger.error(f"Error describing pod: {e}")
        return {"error": str(e)}

@tool(description="Gets the logs from a pod container. Essential for debugging application issues and understanding failure reasons. Supports tail lines and previous container logs.")
async def get_pod_logs(
    pod_name: str,
    namespace: str = "default",
    container: Optional[str] = None,
    tail_lines: int = 100,
    previous: bool = False
) -> Dict[str, Any]:
    """Get pod logs."""
    logger.info(f"Getting logs for pod {pod_name} in namespace {namespace}")
    try:
        logs = v1.read_namespaced_pod_log(
            name=pod_name,
            namespace=namespace,
            container=container,
            tail_lines=tail_lines,
            previous=previous
        )
        
        return {
            "pod": pod_name,
            "namespace": namespace,
            "container": container,
            "logs": logs,
            "lines": len(logs.split('\n'))
        }
    except ApiException as e:
        logger.error(f"Error getting pod logs: {e}")
        return {"error": str(e), "logs": ""}

@tool(description="Lists all deployments in a namespace with replica status and update strategy. Useful for understanding application topology and identifying deployment issues.")
async def list_deployments(namespace: str = "default") -> Dict[str, Any]:
    """List deployments in a namespace."""
    logger.info(f"Listing deployments in namespace: {namespace}")
    try:
        if namespace == "all":
            deployments = apps_v1.list_deployment_for_all_namespaces(watch=False)
        else:
            deployments = apps_v1.list_namespaced_deployment(namespace, watch=False)
        
        deployment_list = []
        for dep in deployments.items:
            deployment_info = {
                "name": dep.metadata.name,
                "namespace": dep.metadata.namespace,
                "replicas": f"{dep.status.ready_replicas or 0}/{dep.spec.replicas}",
                "updated": dep.status.updated_replicas or 0,
                "available": dep.status.available_replicas or 0,
                "age": str(dep.metadata.creation_timestamp),
                "images": [c.image for c in dep.spec.template.spec.containers]
            }
            deployment_list.append(deployment_info)
        
        return {"deployments": deployment_list, "count": len(deployment_list)}
    except ApiException as e:
        logger.error(f"Error listing deployments: {e}")
        return {"error": str(e), "deployments": []}

@tool(description="Gets detailed information about a specific deployment including replicas, conditions, and rollout status. Critical for understanding deployment failures and rollout issues.")
async def describe_deployment(deployment_name: str, namespace: str = "default") -> Dict[str, Any]:
    """Get detailed deployment information."""
    logger.info(f"Describing deployment {deployment_name} in namespace {namespace}")
    try:
        deployment = apps_v1.read_namespaced_deployment(deployment_name, namespace)
        
        deployment_details = {
            "name": deployment.metadata.name,
            "namespace": deployment.metadata.namespace,
            "status": {
                "replicas": deployment.status.replicas or 0,
                "ready_replicas": deployment.status.ready_replicas or 0,
                "updated_replicas": deployment.status.updated_replicas or 0,
                "available_replicas": deployment.status.available_replicas or 0,
                "conditions": [
                    {
                        "type": c.type,
                        "status": c.status,
                        "reason": c.reason,
                        "message": c.message
                    } for c in deployment.status.conditions or []
                ]
            },
            "spec": {
                "replicas": deployment.spec.replicas,
                "strategy": deployment.spec.strategy.type if deployment.spec.strategy else "RollingUpdate",
                "selector": deployment.spec.selector.match_labels,
                "template": {
                    "containers": [
                        {
                            "name": c.name,
                            "image": c.image,
                            "ports": [p.container_port for p in c.ports or []],
                            "resources": c.resources.to_dict() if c.resources else {}
                        } for c in deployment.spec.template.spec.containers
                    ]
                }
            }
        }
        
        return deployment_details
    except ApiException as e:
        logger.error(f"Error describing deployment: {e}")
        return {"error": str(e)}

@tool(description="Lists all services in a namespace with their type, cluster IP, and endpoints. Essential for understanding service discovery and networking issues.")
async def list_services(namespace: str = "default") -> Dict[str, Any]:
    """List services in a namespace."""
    logger.info(f"Listing services in namespace: {namespace}")
    try:
        if namespace == "all":
            services = v1.list_service_for_all_namespaces(watch=False)
        else:
            services = v1.list_namespaced_service(namespace, watch=False)
        
        service_list = []
        for svc in services.items:
            service_info = {
                "name": svc.metadata.name,
                "namespace": svc.metadata.namespace,
                "type": svc.spec.type,
                "cluster_ip": svc.spec.cluster_ip,
                "ports": [
                    f"{p.port}:{p.target_port}/{p.protocol}"
                    for p in svc.spec.ports or []
                ],
                "selector": svc.spec.selector
            }
            service_list.append(service_info)
        
        return {"services": service_list, "count": len(service_list)}
    except ApiException as e:
        logger.error(f"Error listing services: {e}")
        return {"error": str(e), "services": []}

@tool(description="Gets cluster events sorted by timestamp. Critical for understanding the sequence of events during an incident. Can filter by namespace, object type, and reason.")
async def get_events(
    namespace: str = "all",
    limit: int = 50,
    field_selector: Optional[str] = None
) -> Dict[str, Any]:
    """Get cluster events."""
    logger.info(f"Getting events in namespace: {namespace}")
    try:
        if namespace == "all":
            events = v1.list_event_for_all_namespaces(
                limit=limit,
                field_selector=field_selector
            )
        else:
            events = v1.list_namespaced_event(
                namespace,
                limit=limit,
                field_selector=field_selector
            )
        
        event_list = []
        for event in events.items:
            event_info = {
                "namespace": event.metadata.namespace if getattr(event, 'metadata', None) else getattr(event, 'namespace', None),
                "type": event.type,
                "reason": event.reason,
                "object": f"{getattr(event, 'involved_object', {}).kind}/{getattr(event, 'involved_object', {}).name}" if getattr(event, 'involved_object', None) else None,
                "message": event.message,
                "count": getattr(event, 'count', None),
                "first_timestamp": str(getattr(event, 'first_timestamp', getattr(event.metadata, 'creation_timestamp', ''))),
                "last_timestamp": str(getattr(event, 'last_timestamp', getattr(event.metadata, 'creation_timestamp', '')))
            }
            event_list.append(event_info)
        
        # Sort by last_timestamp with safe fallback
        def _ts_key(ev: Dict[str, Any]):
            return ev.get("last_timestamp") or ev.get("first_timestamp") or ""
        event_list.sort(key=_ts_key, reverse=True)
        
        return {"events": event_list, "count": len(event_list)}
    except ApiException as e:
        logger.error(f"Error getting events: {e}")
        return {"error": str(e), "events": []}

@tool(description="Gets node information including capacity, allocatable resources, and conditions. Essential for understanding resource constraints and node health issues.")
async def list_nodes() -> Dict[str, Any]:
    """List cluster nodes with their status and resources."""
    logger.info("Listing cluster nodes")
    try:
        nodes = v1.list_node(watch=False)
        
        node_list = []
        for node in nodes.items:
            # Get node conditions
            conditions = {c.type: c.status for c in node.status.conditions or []}
            
            node_info = {
                "name": node.metadata.name,
                "status": "Ready" if conditions.get("Ready") == "True" else "NotReady",
                "roles": ",".join([
                    label.split("/")[-1] for label in node.metadata.labels
                    if "node-role.kubernetes.io" in label
                ]) or "worker",
                "version": node.status.node_info.kubelet_version,
                "os": node.status.node_info.operating_system,
                "capacity": {
                    "cpu": node.status.capacity.get("cpu"),
                    "memory": node.status.capacity.get("memory"),
                    "pods": node.status.capacity.get("pods")
                },
                "allocatable": {
                    "cpu": node.status.allocatable.get("cpu"),
                    "memory": node.status.allocatable.get("memory"),
                    "pods": node.status.allocatable.get("pods")
                },
                "conditions": conditions
            }
            node_list.append(node_info)
        
        return {"nodes": node_list, "count": len(node_list)}
    except ApiException as e:
        logger.error(f"Error listing nodes: {e}")
        return {"error": str(e), "nodes": []}
