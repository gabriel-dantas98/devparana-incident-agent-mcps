#!/usr/bin/env python

import os
import logging
from typing import Any, Dict, Optional
from dataclasses import dataclass
import time
from langchain_core.tools import tool

import dotenv
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

dotenv.load_dotenv()

# Constants for safety limits
REQUEST_TIMEOUT = 30  # seconds
MAX_LABEL_VALUES = 1000  # maximum number of label values to return
LARGE_RESULT_WARNING_THRESHOLD = 500

@dataclass
class PrometheusConfig:
    url: str

# Initialize config with URL and cookies
config = PrometheusConfig(
    url=os.environ.get("PROMETHEUS_URL", ""),
)

def make_prometheus_request(endpoint: str, params: Optional[Dict[str, str]] = None) -> Any:
    """Make a request to the Prometheus API."""
    if not config.url:
        error_msg = "Prometheus configuration is missing. Please set PROMETHEUS_URL environment variable."
        logger.error(error_msg)
        raise ValueError(error_msg)

    url = f"{config.url.rstrip('/')}/api/v1/{endpoint}"
    logger.debug(f"Making request to Prometheus endpoint: {endpoint}")
    logger.debug(f"Request parameters: {params}")
    
    start_time = time.time()
    try:
        # Make the request with cookies for authentication and timeout
        response = requests.get(
            url,
            params=params,
            timeout=REQUEST_TIMEOUT
        )
        
        response.raise_for_status()
        result = response.json()
        
        if result["status"] != "success":
            error_msg = f"Prometheus API error: {result.get('error', 'Unknown error')}"
            logger.error(error_msg)
            raise ValueError(error_msg)
        
        duration = time.time() - start_time
        logger.info(f"Request to {endpoint} completed successfully in {duration:.2f}s")
        logger.debug(f"Response status: {result['status']}")
        
        return result["data"]
    
    except requests.exceptions.Timeout:
        duration = time.time() - start_time
        logger.error(f"Request to {endpoint} timed out after {duration:.2f}s (timeout: {REQUEST_TIMEOUT}s)")
        raise ValueError(f"Prometheus request timed out after {REQUEST_TIMEOUT} seconds. The query might be too expensive.")
    except requests.exceptions.RequestException as e:
        duration = time.time() - start_time
        logger.error(f"Request to {endpoint} failed after {duration:.2f}s: {str(e)}")
        raise

@tool(description="Execute a PromQL instant query against Prometheus")
async def execute_query(query: str, time: Optional[str] = None) -> Dict[str, Any]:
    """
    Execute an instant query against Prometheus.

    Args:
        query: The PromQL query string to execute.
        time: (Optional) Evaluation timestamp. If not provided, the current server time is used.
    """
    logger.info(f"Executing instant query: {query}")
    logger.debug(f"Query time: {time or 'current'}")
    
    params = {"query": query}
    if time:
        params["time"] = time
    
    try:
        data = make_prometheus_request("query", params=params)
        logger.info(f"Query returned {len(data['result'])} results")
        return {
            "resultType": data["resultType"],
            "result": data["result"]
        }
    except Exception as e:
        logger.error(f"Query execution failed: {str(e)}")
        raise

@tool(description="Execute a PromQL range query with start time, end time, and step interval")
async def execute_range_query(query: str, start: str, end: str, step: str) -> Dict[str, Any]:
    """
    Execute a range query against Prometheus.

    Args:
        query: The PromQL query string to execute.
        start: The start time for the range (RFC3339 or Unix timestamp).
        end: The end time for the range (RFC3339 or Unix timestamp).
        step: Query resolution step width (duration or float in seconds).
    """
    logger.info(f"Executing range query: {query}")
    logger.debug(f"Time range: {start} to {end} with step {step}")
    
    params = {
        "query": query,
        "start": start,
        "end": end,
        "step": step
    }
    
    try:
        data = make_prometheus_request("query_range", params=params)
        logger.info(f"Range query returned {len(data['result'])} series")
        return {
            "resultType": data["resultType"],
            "result": data["result"]
        }
    except Exception as e:
        logger.error(f"Range query execution failed: {str(e)}")
        raise

@tool(description="List all unique values for a label in a specific Prometheus metric")
async def list_metric_label_values(metric: str, label: str) -> Dict[str, Any]:
    """
    Retrieve all unique values for a given label in a specific Prometheus metric.

    This function queries the Prometheus API to find all possible values that the specified
    label (e.g., 'app', 'instance') can take for the provided metric. This is useful for
    exploring the set of label values present in your monitoring data, enabling dynamic
    filtering, grouping, or selection in dashboards and automation.

    IMPORTANT: This function can return large amounts of data and may take time. Results are
    limited to 1000 values to prevent overloading Prometheus. Use specific metrics to get
    more targeted results.

    Args:
        metric: The name of the Prometheus metric to filter by (e.g., 'http_requests_total').
        label: The label name whose values you want to enumerate (e.g., 'app', 'instance').

    Returns:
        A dictionary with:
            - resultType: Always 'label_values'
            - result: A list of unique values for the specified label in the given metric (max 1000).
            - truncated: Boolean indicating if results were truncated due to size limit.
            - total_found: Total number of values found before truncation.
    """
    logger.info(f"Fetching values for label '{label}' of metric '{metric}'")
    
    # Add warning for potentially expensive operation
    logger.warning(f"Executing label values query for metric '{metric}' and label '{label}' - this may be expensive")
    
    try:
        endpoint = f"label/{label}/values"
        params = {"match[]": metric}
        data = make_prometheus_request(endpoint, params=params)
        result = data
        
        total_found = len(result)
        truncated = False
        
        # Limit results to prevent overwhelming response
        if total_found > MAX_LABEL_VALUES:
            result = result[:MAX_LABEL_VALUES]
            truncated = True
            logger.warning(f"Results truncated: found {total_found} values, returning first {MAX_LABEL_VALUES}")
        elif total_found > LARGE_RESULT_WARNING_THRESHOLD:
            logger.warning(f"Large result set: returning {total_found} values for label '{label}' of metric '{metric}'")
        
        logger.info(f"Retrieved {len(result)} unique values for label '{label}' of metric '{metric}' (total found: {total_found})")
        
        return {
            "resultType": "label_values", 
            "result": result,
            "truncated": truncated,
            "total_found": total_found
        }
    except Exception as e:
        logger.error(f"Failed to fetch label values: {str(e)}")
        raise

@tool(description="Get the current active alerts from Prometheus.")
async def get_alerts() -> Dict[str, Any]:
    """
    Retrieves the current active alerts from Prometheus.

    This function queries the Prometheus API to get a list of all active alerts.
    
    Returns:
        A dictionary with:
            - resultType: Always 'alerts'
            - result: A list of active alerts.
    """
    logger.info("Fetching active alerts from Prometheus")
    
    try:
        data = make_prometheus_request("alerts")
        alerts = data.get("alerts", [])
        
        logger.info(f"Retrieved {len(alerts)} active alerts")
        
        return {
            "resultType": "alerts",
            "result": alerts,
        }
    except Exception as e:
        logger.error(f"Failed to fetch alerts: {str(e)}")
        raise
