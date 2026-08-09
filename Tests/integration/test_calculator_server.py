"""
apfel Integration Tests -- bundled MCP calculator server (direct JSON-RPC)

Model-free: talks JSON-RPC over stdio to mcp/calculator/server.py directly,
no apfel binary and no Apple Intelligence needed. Guards #322: the calculator
must never silently return a wrong answer for string-typed arguments (the
on-device model routinely emits {"a":"999","b":"1"}), and must reject
non-numeric arguments as a tool error instead of improvising.

Run: python3 -m pytest Tests/integration/test_calculator_server.py -v
"""

import json
import pathlib
import subprocess

SERVER = pathlib.Path(__file__).parent.parent.parent / "mcp" / "calculator" / "server.py"


def rpc_call(requests):
    """Send JSON-RPC requests to a fresh calculator process, return responses by id."""
    lines = "\n".join(json.dumps(r, separators=(",", ":")) for r in requests) + "\n"
    proc = subprocess.run(
        ["python3", str(SERVER)],
        input=lines, capture_output=True, text=True, timeout=15,
    )
    responses = {}
    for line in proc.stdout.splitlines():
        msg = json.loads(line)
        if "id" in msg and msg["id"] is not None:
            responses[msg["id"]] = msg
    return responses


def call_tool(name, arguments):
    """initialize + tools/call, return (text, is_error)."""
    responses = rpc_call([
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/call",
         "params": {"name": name, "arguments": arguments}},
    ])
    result = responses[2]["result"]
    text = "\n".join(c["text"] for c in result["content"] if c["type"] == "text")
    return text, result.get("isError", False)


def test_add_numeric_args():
    text, is_error = call_tool("add", {"a": 2, "b": 3})
    assert not is_error
    assert text == "5"


def test_add_string_args_are_coerced_not_concatenated():
    """#322: add({"a":"999","b":"1"}) must be 1000, never the string "9991"."""
    text, is_error = call_tool("add", {"a": "999", "b": "1"})
    assert not is_error, f"coercible string args must not error: {text}"
    assert text == "1000", f"Expected 1000, got: {text}"


def test_add_string_float_args_are_coerced():
    text, is_error = call_tool("add", {"a": "2.5", "b": "0.5"})
    assert not is_error
    assert text == "3"


def test_non_numeric_arg_is_a_tool_error_not_a_silent_answer():
    """#322: add({"a":"abc","b":"1"}) previously returned "abc1" as success."""
    text, is_error = call_tool("add", {"a": "abc", "b": "1"})
    assert is_error, f"non-numeric arg must be a tool error, got success: {text}"
    assert "abc" in text


def test_multiply_string_args_are_coerced():
    text, is_error = call_tool("multiply", {"a": "999", "b": "1"})
    assert not is_error, f"coercible string args must not error: {text}"
    assert text == "999"


def test_sqrt_string_arg_is_coerced():
    text, is_error = call_tool("sqrt", {"value": "144"})
    assert not is_error
    assert text == "12"


def test_divide_by_zero_still_errors():
    text, is_error = call_tool("divide", {"a": 1, "b": 0})
    assert is_error
    assert "zero" in text.lower()
