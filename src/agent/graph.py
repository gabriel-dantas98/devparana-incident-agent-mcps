"""LangGraph SRE Agent with Kubernetes and ArgoCD tools integration.

This agent provides intelligent troubleshooting and monitoring capabilities
for Kubernetes environments with ArgoCD GitOps workflows.
"""

from __future__ import annotations

import os
from typing import Any, Dict, Sequence, TypedDict

from langchain_core.messages import BaseMessage
from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent

# Import tools
from tools.argocd import (
    list_applications,
    get_application_status,
    get_application_logs,
    get_application_events
)

from tools.k8s import (
    list_pods,
    describe_pod,
    get_pod_logs,
    list_deployments,
    describe_deployment,
    list_services,
    get_events,
    list_nodes
)

from tools.prometheus import (
    execute_query,
    execute_range_query,
    get_alerts,
    list_metric_label_values
)

from tools.backstage import (
    list_entities,
    get_entity_metadata,
    search_entities_by_attribute,
    search_catalog_entities,
    list_entity_attributes,
)

from agent.constants import SYSTEM_PROMPT

class Context(TypedDict):
    """Context parameters for the agent.

    Set these when creating assistants OR when invoking the graph.
    See: https://langchain-ai.github.io/langgraph/cloud/how-tos/configuration_cloud/
    """

    my_configurable_param: str


class State(TypedDict):
    """Input state for the agent.

    Defines the initial structure of incoming data.
    See: https://langchain-ai.github.io/langgraph/concepts/low_level/#state
    """

    messages: Sequence[BaseMessage]
    memory: Dict[str, Any]


def create_sre_agent():
    """Create and configure the SRE React Agent with all tools."""

    model = ChatOpenAI(
        model="gpt-5-mini-2025-08-07",
        temperature=0.1,  # Low temperature for consistent technical responses
        api_key=os.getenv("OPENAI_API_KEY")
    )
    
    tools = [
        # ArgoCD tools
        list_applications,
        get_application_status,
        get_application_logs,
        get_application_events,
        # Kubernetes tools
        list_pods,
        describe_pod,
        get_pod_logs,
        list_deployments,
        describe_deployment,
        list_services,
        get_events,
        list_nodes,
        # Prometheus tools
        execute_query,
        execute_range_query,
        list_metric_label_values,
        get_alerts,

        # Backstage tools
        list_entities,
        get_entity_metadata,
        search_entities_by_attribute,
        search_catalog_entities,
        list_entity_attributes,
    ]

    agent = create_react_agent(
        model=model,
        tools=tools,
        prompt=SYSTEM_PROMPT
    )
    
    return agent

graph = create_sre_agent()
