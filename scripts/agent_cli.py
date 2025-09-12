#!/usr/bin/env python3

import os
import sys
import json
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv


def load_env_files(repo_root: Path) -> None:
    candidates = [
        repo_root / ".env",
        repo_root / ".env.local",
        repo_root / ".env.argocd",
        repo_root / ".argocd.env",
    ]
    for env_file in candidates:
        if env_file.exists():
            load_dotenv(env_file, override=False)


def ensure_sys_path(repo_root: Path) -> None:
    src_dir = repo_root / "src"
    if str(src_dir) not in sys.path:
        sys.path.insert(0, str(src_dir))


def get_prompt_from_args() -> Optional[str]:
    if len(sys.argv) > 1:
        return " ".join(sys.argv[1:]).strip()
    if not sys.stdin.isatty():
        data = sys.stdin.read().strip()
        if data:
            return data
    return None


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]

    # Prepare environment
    load_env_files(repo_root)
    ensure_sys_path(repo_root)

    prompt = get_prompt_from_args()
    if not prompt:
        print("Usage: agent_cli.py <prompt text>\n       echo 'your prompt' | agent_cli.py", file=sys.stderr)
        return 2

    if not os.getenv("OPENAI_API_KEY"):
        print("ERROR: OPENAI_API_KEY is not set in environment or .env files.", file=sys.stderr)
        return 3

    # Lazy imports after sys.path is set
    from langchain_core.messages import HumanMessage
    from agent.graph import graph

    try:
        state = {"messages": [HumanMessage(content=prompt)], "memory": {}}
        result = graph.invoke(state)
        # Print last assistant message content if available
        if isinstance(result, dict) and "messages" in result and result["messages"]:
            last = result["messages"][-1]
            content = getattr(last, "content", None)
            if content:
                print(content)
                return 0
        # Fallback: pretty print
        print(json.dumps(result, default=str, indent=2))
        return 0
    except Exception as e:
        print(f"Agent invocation failed: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

