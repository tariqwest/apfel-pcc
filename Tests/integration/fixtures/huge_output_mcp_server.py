#!/usr/bin/env python3
"""MCP server fixture whose tool returns a huge result (#221).

`fetch_document` returns ~40 KB of text (well over the 4096-token window),
framed with a distinct HEAD marker at the very start and TAIL marker at the very
end. apfel must token-budget-truncate this head+tail before the follow-up
prompt: in CLI mode the un-truncated result overflowed the context window after
the tool already ran; in server mode the context trimmer dropped the oversized
tool message whole while still instructing the model to answer from it. After
truncation the request completes normally and both markers survive (head+tail).
"""

import json
import sys

HEAD = "DOCUMENT_HEAD_MARKER_ALPHA. "
TAIL = " DOCUMENT_TAIL_MARKER_OMEGA."
FILLER = ("The quick brown fox jumps over the lazy dog. " * 900)
BIG_DOCUMENT = HEAD + FILLER + TAIL


def send(msg):
    sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def respond(msg_id, result):
    send({"jsonrpc": "2.0", "id": msg_id, "result": result})


def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        msg = json.loads(line)
        method = msg.get("method")
        msg_id = msg.get("id")

        if method == "initialize":
            respond(msg_id, {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "huge-output-mcp", "version": "1.0.0"},
            })
        elif method == "notifications/initialized":
            continue
        elif method == "tools/list":
            respond(msg_id, {
                "tools": [{
                    "name": "fetch_document",
                    "description": "Fetch the full text of the document",
                    "inputSchema": {"type": "object", "properties": {}},
                }]
            })
        elif method == "tools/call":
            respond(msg_id, {
                "content": [{"type": "text", "text": BIG_DOCUMENT}],
                "isError": False,
            })


if __name__ == "__main__":
    main()
