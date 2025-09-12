# New LangGraph Project

[![CI](https://github.com/langchain-ai/new-langgraph-project/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/langchain-ai/new-langgraph-project/actions/workflows/unit-tests.yml)
[![Integration Tests](https://github.com/langchain-ai/new-langgraph-project/actions/workflows/integration-tests.yml/badge.svg)](https://github.com/langchain-ai/new-langgraph-project/actions/workflows/integration-tests.yml)

This template demonstrates a simple application implemented using [LangGraph](https://github.com/langchain-ai/langgraph), designed for showing how to get started with [LangGraph Server](https://langchain-ai.github.io/langgraph/concepts/langgraph_server/#langgraph-server) and using [LangGraph Studio](https://langchain-ai.github.io/langgraph/concepts/langgraph_studio/), a visual debugging IDE.

<div align="center">
  <img src="./static/studio_ui.png" alt="Graph view in LangGraph studio UI" width="75%" />
</div>

The core logic defined in `src/agent/graph.py`, showcases an single-step application that responds with a fixed string and the configuration provided.

You can extend this graph to orchestrate more complex agentic workflows that can be visualized and debugged in LangGraph Studio.

## Getting Started

1. Install dependencies, along with the [LangGraph CLI](https://langchain-ai.github.io/langgraph/concepts/langgraph_cli/), which will be used to run the server.

```bash
cd path/to/your/app
pip install -e . "langgraph-cli[inmem]"
```

2. (Optional) Customize the code and project as needed. Create a `.env` file if you need to use secrets.

```bash
cp .env.example .env
```

If you want to enable LangSmith tracing, add your LangSmith API key to the `.env` file.

```text
# .env
LANGSMITH_API_KEY=lsv2...
```

3. Start the LangGraph Server.

```shell
langgraph dev
```

For more information on getting started with LangGraph Server, [see here](https://langchain-ai.github.io/langgraph/tutorials/langgraph-platform/local-server/).

## Local Kubernetes + ArgoCD (optional)

The `cluster/` folder contains Kind + ArgoCD + Prometheus + Grafana helpers.

- Single entrypoint: `make setup` (calls `cluster/scripts/setup.sh`).
- On bootstrap, setup auto-creates an ArgoCD `Application` that points to `cluster/resources/sample-apps` in this repo with automated sync enabled. ArgoCD will immediately sync the `sample-apps` namespace.

Manual apply of the sample app (if needed):

```bash
kubectl apply -f cluster/resources/sample-apps/nginx-deployment.yaml
```

### Prometheus & Websearch configuration

- Set `PROMETHEUS_URL` to enable Prometheus tools (instant/range queries and label values). For local kind with the provided manifests:

```bash
kubectl -n monitoring port-forward svc/prometheus 9090:9090
export PROMETHEUS_URL=http://localhost:9090
```

- Optional web search tool (for docs/runbooks). Use Tavily:

```bash
export TAVILY_API_KEY="..."
```

Run the integration tests against your cluster:

```bash
OPENAI_API_KEY=... python test_agent_integration.py
```

## How to customize

1. **Define runtime context**: Modify the `Context` class in the `graph.py` file to expose the arguments you want to configure per assistant. For example, in a chatbot application you may want to define a dynamic system prompt or LLM to use. For more information on runtime context in LangGraph, [see here](https://langchain-ai.github.io/langgraph/agents/context/?h=context#static-runtime-context).

2. **Extend the graph**: The core logic of the application is defined in [graph.py](./src/agent/graph.py). You can modify this file to add new nodes, edges, or change the flow of information.

## Development

While iterating on your graph in LangGraph Studio, you can edit past state and rerun your app from previous states to debug specific nodes. Local changes will be automatically applied via hot reload.

Follow-up requests extend the same thread. You can create an entirely new thread, clearing previous history, using the `+` button in the top right.

For more advanced features and examples, refer to the [LangGraph documentation](https://langchain-ai.github.io/langgraph/). These resources can help you adapt this template for your specific use case and build more sophisticated conversational agents.

LangGraph Studio also integrates with [LangSmith](https://smith.langchain.com/) for more in-depth tracing and collaboration with teammates, allowing you to analyze and optimize your chatbot's performance.

---

## Discord chatbot (integrated with `agent`)

The Discord bot in `src/vibedebugger_discord/chatbot.py` forwards messages to the `agent.graph` and sends back the agent's reply.

Required environment variables:

```bash
# LLM
export OPENAI_API_KEY=...

# Discord
export DISCORD_TOKEN=...  # Bot token
# (optional fallback) DISCORD_PUBLIC_KEY=...

# Optional tools
export PROMETHEUS_URL=...
export TAVILY_API_KEY=...
```

Run locally:

```bash
python -m src.vibedebugger_discord.chatbot
```

Notes:
- Ensure your bot has the Message Content Intent enabled in the Discord developer portal, or the bot will not receive message text.
- The bot trims replies to <= 1900 chars to fit Discord limits.
