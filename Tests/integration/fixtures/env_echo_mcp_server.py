#!/usr/bin/env python3
"""MCP server fixture that reflects its own environment through tool names (#229).

At startup it inspects os.environ and exposes:
  - a sentinel tool ``env_report`` (always present, proves the server ran),
  - a ``leaked_<name>`` tool for every canary secret it can still see, and
  - a ``saw_<name>`` tool for every allowlisted passthrough var it received.

apfel prints each connection's tool names on startup, so a model-free test can
assert on the banner: no ``leaked_*`` tool means the child never inherited the
secret; ``saw_pythonpath`` means the allowlisted PYTHON var passed through.

This exercises the env-scrubbing fix: local MCP subprocesses must NOT inherit
APFEL_TOKEN/APFEL_MCP_TOKEN or any TOKEN/KEY/SECRET var from the parent shell.
"""

import json
import os
import sys

# Secrets that must NEVER reach the child. The test injects these into apfel's
# environment before spawning; the scrubber must strip them.
CANARY_SECRETS = [
    "APFEL_TOKEN",
    "APFEL_MCP_TOKEN",
    "APFEL_HOST",
    "TEST_CANARY_SECRET",
    "TEST_CANARY_API_KEY",
    "TEST_CANARY_TOKEN",
]

# Allowlisted vars the child legitimately needs. The test injects a PYTHONPATH
# canary and expects it to pass through.
PASSTHROUGH_VARS = ["PATH", "HOME", "PYTHONPATH", "LC_ALL"]


def build_tools():
    tools = [{
        "name": "env_report",
        "description": "sentinel tool proving the fixture started",
        "inputSchema": {"type": "object", "properties": {}},
    }]
    for name in CANARY_SECRETS:
        if os.environ.get(name):
            tools.append({
                "name": f"leaked_{name.lower()}",
                "description": f"the child could still see {name}",
                "inputSchema": {"type": "object", "properties": {}},
            })
    for name in PASSTHROUGH_VARS:
        if os.environ.get(name):
            tools.append({
                "name": f"saw_{name.lower()}",
                "description": f"the child received {name}",
                "inputSchema": {"type": "object", "properties": {}},
            })
    return tools


TOOLS = build_tools()


def send(msg):
    sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def respond(msg_id, result):
    send({"jsonrpc": "2.0", "id": msg_id, "result": result})


def handle(msg):
    method = msg.get("method")
    msg_id = msg.get("id")
    if method == "initialize":
        respond(msg_id, {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "env-echo-mcp", "version": "1.0.0"},
        })
    elif method == "notifications/initialized":
        return
    elif method == "tools/list":
        respond(msg_id, {"tools": TOOLS})
    elif method == "tools/call":
        respond(msg_id, {"content": [{"type": "text", "text": "ok"}]})
    elif msg_id is not None:
        respond(msg_id, {})


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        handle(msg)


if __name__ == "__main__":
    main()
