#!/usr/bin/env python

import os
import logging
import requests
import dotenv
from typing import Any, Dict, List, Optional
from dataclasses import dataclass
from langchain_core.tools import tool

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

dotenv.load_dotenv()
logger.info("Initializing Backstage MCP Server")

@dataclass
class BackstageConfig:
    url: str

config = BackstageConfig(
    url=os.environ.get("BACKSTAGE_BASE_URL", "")
)

def backstage_request(endpoint: str, params: Optional[Dict[str, str]] = None) -> Any:
    """Make a request to the Backstage catalog API."""
    if not config.url:
        raise ValueError("Backstage catalog URL is not set.")
    url = f"{config.url.rstrip('/')}/{endpoint.lstrip('/')}"
    logger.debug(f"Requesting Backstage endpoint: {url}")
    resp = requests.get(url, params=params)
    resp.raise_for_status()
    return resp.json()

@tool(description="List all entities of a given kind and optional type (e.g., teams, lines, services, users, systems). Use this tool when you don't have context or are unsure about specific entity names.")
async def list_entities(kind: str, type: Optional[str] = None) -> List[Dict[str, Any]]:
    """
    Returns all entities of a given kind (component, group, user, system, etc). Optionally filter by spec.type (e.g., team, line, service).
    This function should be used as the first step when exploring the catalog or when you don't have specific entity names in mind.
    """
    filter_str = f"kind={kind}"
    if type:
        filter_str += f",spec.type={type}"
    data = backstage_request("entities", {"filter": filter_str})
    return data

@tool(description="Get metadata for a specific entity by kind and name")
async def get_entity_metadata(kind: str, name: str) -> Dict[str, Any]:
    """
    Returns the full metadata for a given entity (component, group, user, system, etc).
    """
    data = backstage_request("entities", {"filter": f"kind={kind},metadata.name={name}"})

    if not data:
        return {}
    return data[0]

@tool(description="Search entities by attribute and value")
async def search_entities_by_attribute(kind: str, attribute: str, value: str) -> List[Dict[str, Any]]:
    """
    Returns all entities of a given kind where the given attribute matches the specified value.
    Args:
        kind: The entity kind (component, group, etc)
        attribute: The attribute key (e.g., 'spec.tier', 'spec.type', 'metadata.annotations.some_key')
        value: The value to match
    """
    data = backstage_request("entities", {"filter": f"kind={kind},{attribute}={value}"})
    return data

@tool(description="Search for entities in the software catalog using a search term. Supports fuzzy matching based on Backstage's search capabilities.")
async def search_catalog_entities(term: str) -> List[Dict[str, Any]]:
    """
    Searches the Backstage catalog using the provided term.
    The search is performed across various entity fields and types within the 'software-catalog'.
    Args:
        term: The search term to query for.
    """
    endpoint = "api/search/query"
    params = {
        "term": term,
        "types[0]": "software-catalog"
    }
    logger.info(f"Searching Backstage catalog with term: '{term}'")
    data = backstage_request(endpoint, params)

    return data.get("results", [])

@tool(description="List all attribute keys for a given entity. Useful for schema discovery and dynamic UI generation.")
async def list_entity_attributes(kind: str, name: str) -> List[str]:
    """
    Returns a flat list of all attribute keys (dot notation) for a given entity.
    Args:
        kind: The entity kind (component, group, etc)
        name: The entity name (metadata.name)
    """
    def flatten_keys(d, prefix=''):
        keys = []
        for k, v in d.items():
            full_key = f"{prefix}.{k}" if prefix else k
            keys.append(full_key)
            if isinstance(v, dict):
                keys.extend(flatten_keys(v, full_key))
        return keys
    data = backstage_request("entities", {"filter": f"kind={kind},metadata.name={name}"})
    if not data:
        return []
    entity = data[0]
    return flatten_keys(entity)
