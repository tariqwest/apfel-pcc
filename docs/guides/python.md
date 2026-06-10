# How to use the Apple Foundation Model from Python

Call Apple's on-device Foundation Model from Python using the official `openai` SDK, pointed at a local `apfel-plus --serve`. 100% on-device, zero API cost, no network required for inference.

This guide shows the canonical patterns: one-shot completion, streaming, JSON mode, error handling, tool calling, and a real text-summarization example. Every code block was run against a live apfel-plus server; the output below each snippet is the real unedited stdout.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/python](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/python).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (default port `11434`)
- Python 3.11+
- `pip install openai` (or `uv add openai`)

## 1. One-shot chat completion

Point the `openai` SDK at your local apfel-plus server and call `chat.completions.create`:

```python
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

response = client.chat.completions.create(
    model="apple-foundationmodel",
    messages=[
        {"role": "user", "content": "In one sentence, what is the Swift programming language?"},
    ],
    max_tokens=80,
)

print((response.choices[0].message.content or "").strip())
```

Real output:

```text
Swift is a modern, high-performance, and safe programming language developed by Apple for developing iOS, macOS, watchOS, and tvOS applications.
```

Lab script: [`01_oneshot.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/01_oneshot.py).

## 2. Streaming

Pass `stream=True` and iterate. Guard against empty `choices` on the final usage chunk:

```python
import sys
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

stream = client.chat.completions.create(
    model="apple-foundationmodel",
    messages=[{"role": "user", "content": "List three Apple silicon chips, one per line."}],
    max_tokens=80,
    stream=True,
)

for chunk in stream:
    if not chunk.choices:
        continue
    delta = chunk.choices[0].delta.content or ""
    sys.stdout.write(delta)
    sys.stdout.flush()
print()
```

Real output:

```text
Apple M1  
Apple M2  
Apple M3
```

Lab script: [`02_stream.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/02_stream.py).

## 3. JSON mode / structured output

Request `response_format: {"type": "json_object"}` and parse. apfel-plus may wrap output in markdown fences - the fence-strip regex below handles both cases cleanly:

```python
import json, re
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

response = client.chat.completions.create(
    model="apple-foundationmodel",
    messages=[{
        "role": "user",
        "content": "Return JSON with fields 'chip', 'year', 'cores'. Describe the Apple M1 chip. Return ONLY JSON.",
    }],
    response_format={"type": "json_object"},
    max_tokens=120,
)

raw = (response.choices[0].message.content or "").strip()
raw = re.sub(r"^```(?:json)?\s*|\s*```$", "", raw, flags=re.MULTILINE).strip()
data = json.loads(raw)
print(json.dumps(data, indent=2, sort_keys=True))
```

Real output:

```json
{
  "chip": "Apple M1",
  "cores": 8,
  "year": 2020
}
```

Lab script: [`03_json.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/03_json.py).

## 4. Error handling

apfel-plus returns honest HTTP errors for unsupported features. Embeddings return `501`:

```python
from openai import APIStatusError, OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

try:
    client.embeddings.create(
        model="apple-foundationmodel",
        input="apfel-plus runs 100% on-device.",
    )
except APIStatusError as e:
    print(f"Got expected error: HTTP {e.status_code} - {e.message}")
```

Real output:

```text
Got expected error: HTTP 501 - Error code: 501 - {'error': {'message': "Embeddings not supported by Apple's on-device model.", 'type': 'invalid_request_error'}}
```

Lab script: [`04_errors.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/04_errors.py).

## 5. Tool calling

Define a tool schema, send a prompt, handle the tool call, post the result, get the final answer:

```python
import json
from openai import OpenAI

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

TOOLS = [{
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get the current temperature in Celsius for a city.",
        "parameters": {
            "type": "object",
            "properties": {"city": {"type": "string", "description": "City name"}},
            "required": ["city"],
        },
    },
}]


def get_weather(city: str, **_: object) -> str:
    fake = {"Vienna": 14, "Cupertino": 19, "Tokyo": 11}
    return json.dumps({"city": city, "temp_c": fake.get(city, 15)})


messages = [{"role": "user", "content": "What is the temperature in Vienna right now?"}]

first = client.chat.completions.create(
    model="apple-foundationmodel", messages=messages, tools=TOOLS, max_tokens=256,
)

msg = first.choices[0].message
messages.append(msg.model_dump(exclude_none=True))

if msg.tool_calls:
    for call in msg.tool_calls:
        args = json.loads(call.function.arguments)
        result = get_weather(**args)
        messages.append({"role": "tool", "tool_call_id": call.id, "content": result})

    final = client.chat.completions.create(
        model="apple-foundationmodel", messages=messages, max_tokens=120,
    )
    print((final.choices[0].message.content or "").strip())
```

Real output:

```text
The current temperature in Vienna is 14°C.
```

Lab script: [`05_tools.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/05_tools.py).

## 6. Real example - summarize a file from stdin

```python
import sys
from openai import OpenAI

text = sys.stdin.read().strip()
if not text:
    sys.exit("usage: cat file.txt | python 06_example.py")

client = OpenAI(base_url="http://localhost:11434/v1", api_key="not-needed")

response = client.chat.completions.create(
    model="apple-foundationmodel",
    messages=[
        {"role": "system", "content": "You are a concise summarizer. Reply with one short paragraph."},
        {"role": "user", "content": f"Summarize:\n\n{text}"},
    ],
    max_tokens=150,
)
print((response.choices[0].message.content or "").strip())
```

```bash
cat README.md | python 06_example.py
```

Real output (summarizing a paragraph about the M1 chip):

```text
The Apple M1 chip, released in November 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It features an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores. The chip combines CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.py`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/python/06_example.py).

## Troubleshooting

- **`Connection refused` on port 11434** - run `apfel-plus --serve` first.
- **`Embeddings not supported`** - apfel-plus is text-only; use sentence-transformers or another embedder for vectors.
- **`JSONDecodeError` in JSON mode** - keep the fence-strip regex; apfel-plus sometimes wraps JSON in `` ```json ... ``` ``.
- **Empty streaming output** - make sure your client handles the final `usage` chunk with empty `choices`. The `if not chunk.choices: continue` above covers it.
- **Model refuses a tool call** - small on-device models occasionally decline. Retry the whole call.

## Tested with

- apfel-plus v1.0.3
- macOS 26.3.1, Apple Silicon
- Python 3.11 / openai 2.31.0
- Date: 2026-04-16

Full runnable test suite + captured outputs: [apfel-guides-lab/tests/test_python.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_python.py).

## See also

- [nodejs.md](nodejs.md) - same thing from Node.js
- [ruby.md](ruby.md) / [php.md](php.md) - same thing from Ruby / PHP
- [bash-curl.md](bash-curl.md) - raw HTTP, no SDK
- [Arthur-Ficial/apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab) - runnable proof for all ten languages
