# How to use the Apple Foundation Model from Bash / curl

Call Apple's on-device Foundation Model from plain Bash with `curl` and `jq` - no SDK, no dependencies beyond what's already on macOS. 100% on-device, zero API cost.

Perfect for CI pipelines, one-liners, and quick smoke tests. Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/bash-curl](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/bash-curl).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus jq` (`curl` and `bash` already on every Mac)
- `apfel-plus --serve` running (port `11434`)

## 1. One-shot

```bash
curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-foundationmodel",
    "messages": [{"role": "user", "content": "In one sentence, what is the Swift programming language?"}],
    "max_tokens": 80
  }' \
  | jq -r '.choices[0].message.content'
```

Real output:

```text
Swift is a modern, high-performance programming language developed by Apple for developing iOS, macOS, watchOS, and tvOS applications.
```

Lab script: [`01_oneshot.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/01_oneshot.sh).

## 2. Streaming

```bash
curl -sS -N http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-foundationmodel","messages":[{"role":"user","content":"List three Apple silicon chips, one per line."}],"max_tokens":80,"stream":true}' \
  | while IFS= read -r line; do
      line="${line#data: }"
      [[ -z "$line" || "$line" == "[DONE]" ]] && continue
      content=$(printf '%s' "$line" | jq -r '.choices[0].delta.content // empty' 2>/dev/null || true)
      [[ -n "$content" ]] && printf '%s' "$content"
    done
echo
```

Real output:

```text
Here are three Apple silicon chips:

- M1
- M2
- M3
```

Lab script: [`02_stream.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/02_stream.sh).

## 3. JSON mode

```bash
raw=$(curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "apple-foundationmodel",
    "messages": [{"role": "user", "content": "Return JSON with fields chip, year, cores. Describe the Apple M1 chip. Return ONLY JSON."}],
    "response_format": {"type": "json_object"},
    "max_tokens": 120
  }' \
  | jq -r '.choices[0].message.content')

raw=$(printf '%s' "$raw" | sed -E 's/^```(json)?//; s/```$//' | tr -d '\r')
printf '%s' "$raw" | jq '.'
```

Real output:

```json
{
  "chip": "Apple M1",
  "year": 2020,
  "cores": {
    "CPU": {
      "Cores": 8,
      "Threads": 8
    },
    "GPU": {
      "Cores": 16
    }
  }
}
```

Lab script: [`03_json.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/03_json.sh).

## 4. Error handling

Capture HTTP status with `-w '%{http_code}'`:

```bash
tmp=$(mktemp)
http_status=$(curl -sS -o "$tmp" -w '%{http_code}' \
  http://localhost:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-foundationmodel","input":"apfel-plus runs 100% on-device."}')

if [[ "$http_status" -ge 400 ]]; then
  msg=$(jq -r '.error.message // empty' "$tmp" 2>/dev/null || true)
  echo "Got expected error: HTTP $http_status - ${msg:-see response}"
fi
rm -f "$tmp"
```

Real output:

```text
Got expected error: HTTP 501 - Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/04_errors.sh).

## 5. Tool calling

Raw curl round-trip: model asks for a tool call, we answer, model replies:

```bash
tools='[{
  "type":"function",
  "function":{
    "name":"get_weather",
    "description":"Get the current temperature in Celsius for a city.",
    "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
  }
}]'

first=$(jq -n --argjson tools "$tools" '{
  model: "apple-foundationmodel",
  messages: [{role:"user", content:"What is the temperature in Vienna right now?"}],
  tools: $tools,
  max_tokens: 256
}' | curl -sS http://localhost:11434/v1/chat/completions \
       -H "Content-Type: application/json" -d @-)

msg=$(jq -c '.choices[0].message' <<<"$first")
call=$(jq -c '.tool_calls[0]' <<<"$msg")
city=$(jq -r '.function.arguments | fromjson | .city' <<<"$call")

tool_result=$(jq -cn --arg c "$city" --argjson t 14 '{city:$c, temp_c:$t}')
tool_msg=$(jq -cn --arg id "$(jq -r '.id' <<<"$call")" --arg content "$tool_result" \
  '{role:"tool", tool_call_id:$id, content:$content}')

final_payload=$(jq -n --argjson msg "$msg" --argjson tool "$tool_msg" '{
  model:"apple-foundationmodel",
  messages:[{role:"user",content:"What is the temperature in Vienna right now?"}, $msg, $tool],
  max_tokens:120
}')

curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" -d "$final_payload" \
  | jq -r '.choices[0].message.content'
```

Real output:

```text
The current temperature in Vienna is 14 degrees Celsius.
```

Lab script: [`05_tools.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/05_tools.sh).

## 6. Real example - summarize a file

```bash
text=$(cat "$1")
payload=$(jq -n --arg text "$text" '{
  model:"apple-foundationmodel",
  messages:[
    {role:"system", content:"You are a concise summarizer. Reply with one short paragraph."},
    {role:"user", content: ("Summarize:\n\n" + $text)}
  ],
  max_tokens:150
}')
curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" -d "$payload" \
  | jq -r '.choices[0].message.content'
```

Usage: `bash 06_example.sh README.md`.

Real output:

```text
The Apple M1 chip, released in November 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It features an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores. The chip unified CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.sh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/bash-curl/06_example.sh).

## Troubleshooting

- **`jq: command not found`** - `brew install jq`.
- **Empty streamed output** - the OpenAI SSE format prefixes each line with `data: ` - don't forget to strip it.
- **Hard to escape JSON** - use `jq -n --arg text "..."` to build payloads; never concatenate strings.

## Tested with

<<<<<<< HEAD
- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
=======
- apfel v1.0.3 / macOS 26.3.1 Apple Silicon (original capture; the CLI and HTTP surfaces used here are release-gated by apfel's test suite on every version)
>>>>>>> upstream/main
- Bash 5.3 / jq 1.7 / curl (system)
- Date: 2026-04-16

Runnable tests: [tests/test_bash_curl.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_bash_curl.py).

## See also

[zsh.md](zsh.md), [python.md](python.md), [nodejs.md](nodejs.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
