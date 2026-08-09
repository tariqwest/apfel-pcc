#!/usr/bin/env python3
"""MCP server fixture that dies after the handshake.

It answers initialize + tools/list (so apfel registers the `multiply` tool and
the server becomes healthy) and then exits before any tools/call arrives. The
next tool call therefore writes to a pipe whose read end is closed. Used to
prove apfel no longer dies with SIGPIPE (issue #215) when a downstream MCP
server crashes between calls.
"""

import json
import sys


def read_message():
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line.strip())


def send(msg):
    sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def respond(msg_id, result):
    send({"jsonrpc": "2.0", "id": msg_id, "result": result})


def main():
    while True:
        msg = read_message()
        if msg is None:
            break
        method = msg.get("method")
        msg_id = msg.get("id")

        if method == "initialize":
            respond(msg_id, {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "crashing-mcp", "version": "1.0.0"},
            })
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            respond(msg_id, {
                "tools": [{
                    "name": "multiply",
                    "description": "Multiply two numbers",
                    "inputSchema": {
                        "type": "object",
                        "properties": {
                            "a": {"type": "number"},
                            "b": {"type": "number"},
                        },
                        "required": ["a", "b"],
                    },
                }]
            })
            # Crash: exit right after advertising tools, before any tools/call.
            sys.stdout.close()
            sys.exit(0)


if __name__ == "__main__":
    main()
