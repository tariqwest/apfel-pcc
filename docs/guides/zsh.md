# How to use the Apple Foundation Model from Zsh

Call Apple's on-device Foundation Model from Zsh - the default shell on modern macOS. Zsh's parameter expansion, associative arrays, and `print -r` make raw HTTP calls more concise than the Bash equivalent.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/zsh](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/zsh).

## Prerequisites

- macOS 26+ Tahoe (Zsh 5.9+ ships with the OS)
- `brew install apfel-plus jq`
- `apfel-plus --serve` running (port `11434`)

## 1. One-shot

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset

local -A req=(
  model "apple-foundationmodel"
  prompt "In one sentence, what is the Swift programming language?"
)

local payload="$(jq -cn --arg m "$req[model]" --arg p "$req[prompt]" \
  '{model:$m, messages:[{role:"user", content:$p}], max_tokens:80}')"

curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" -d "$payload" \
  | jq -r '.choices[0].message.content'
```

Real output:

```text
Swift is a modern, high-performance programming language developed by Apple for developing apps and systems on iOS, macOS, watchOS, and tvOS.
```

Lab script: [`01_oneshot.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/01_oneshot.zsh).

## 2. Streaming

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset no_xtrace no_verbose

curl -sS -N http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-foundationmodel","messages":[{"role":"user","content":"List three Apple silicon chips, one per line."}],"max_tokens":80,"stream":true}' \
  | while IFS= read -r line; do
      line=${line#data: }
      [[ -z $line || $line == "[DONE]" ]] && continue
      piece=$(print -r -- "$line" | jq -r '.choices[0].delta.content // empty' 2>/dev/null) || piece=
      [[ -n $piece ]] && print -rn -- "$piece"
    done
print
```

Real output:

```text
Apple M1
Apple M2
Apple M2 Pro
```

Lab script: [`02_stream.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/02_stream.zsh).

## 3. JSON mode

Zsh parameter expansion strips markdown fences without calling `sed`:

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset

local raw
raw=$(curl -sS http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model":"apple-foundationmodel",
    "messages":[{"role":"user","content":"Return JSON with fields chip, year, cores. Describe the Apple M1 chip. Return ONLY JSON."}],
    "response_format":{"type":"json_object"},
    "max_tokens":120
  }' | jq -r '.choices[0].message.content')

raw=${raw#\`\`\`json}
raw=${raw#\`\`\`}
raw=${raw%\`\`\`}
raw=${raw//$'\r'/}

print -r -- "$raw" | jq '.'
```

Real output:

```json
{
  "chip": "Apple M1",
  "year": 2020,
  "cores": {
    "CPU": 8,
    "GPU": 8
  }
}
```

Lab script: [`03_json.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/03_json.zsh).

## 4. Error handling

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset

local tmp=$(mktemp)
local http_status
http_status=$(curl -sS -o "$tmp" -w '%{http_code}' \
  http://localhost:11434/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"apple-foundationmodel","input":"apfel-plus runs 100% on-device."}')

if (( http_status >= 400 )); then
  local msg=$(jq -r '.error.message // empty' "$tmp" 2>/dev/null) || true
  print -r -- "Got expected error: HTTP ${http_status} - ${msg:-see response}"
fi
rm -f "$tmp"
```

Real output:

```text
Got expected error: HTTP 501 - Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/04_errors.zsh).

## 5. Tool calling

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset

local tools='[{
  "type":"function",
  "function":{
    "name":"get_weather",
    "description":"Get the current temperature in Celsius for a city.",
    "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}
  }
}]'

local first
first=$(jq -n --argjson tools "$tools" '{
  model:"apple-foundationmodel",
  messages:[{role:"user", content:"What is the temperature in Vienna right now?"}],
  tools:$tools,
  max_tokens:256
}' | curl -sS http://localhost:11434/v1/chat/completions \
       -H "Content-Type: application/json" -d @-)

local msg=$(jq -c '.choices[0].message' <<<"$first")
local call=$(jq -c '.tool_calls[0]' <<<"$msg")
local city=$(jq -r '.function.arguments | fromjson | .city' <<<"$call")
local -A fake=(Vienna 14 Cupertino 19 Tokyo 11)
local temp=${fake[$city]:-15}

local tool_result=$(jq -cn --arg c "$city" --argjson t "$temp" '{city:$c, temp_c:$t}')
local tool_msg=$(jq -cn --arg id "$(jq -r '.id' <<<"$call")" --arg content "$tool_result" \
  '{role:"tool", tool_call_id:$id, content:$content}')

local final_payload=$(jq -n --argjson msg "$msg" --argjson tool "$tool_msg" '{
  model:"apple-foundationmodel",
  messages:[{role:"user", content:"What is the temperature in Vienna right now?"}, $msg, $tool],
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

Lab script: [`05_tools.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/05_tools.zsh).

## 6. Real example - summarize stdin

```zsh
#!/bin/zsh
emulate -L zsh
setopt err_exit pipe_fail no_unset

local text=$(cat)
[[ -z $text ]] && { print -u 2 -- "usage: cat file.txt | zsh 06_example.zsh"; exit 1 }

local payload=$(jq -n --arg text "$text" '{
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

Real output:

```text
The Apple M1 chip, released in 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It features an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores, providing significant performance-per-watt improvements over Intel chips.
```

Lab script: [`06_example.zsh`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/zsh/06_example.zsh).

## Troubleshooting

- **`local piece` prints the assignment** - Zsh prints declarations when used outside functions with `no_unset`. Drop the `local` or wrap the block in a function. The streaming script above shows the clean pattern.
- **Scripts using Bash heredocs don't work** - Zsh's quoting rules differ slightly. The scripts above use single-quoted payloads or `jq -n --arg` to sidestep it.

## Tested with

- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
- zsh 5.9 (system) / jq 1.7
- Date: 2026-04-16

Runnable tests: [tests/test_zsh.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_zsh.py).

## See also

[bash-curl.md](bash-curl.md), [applescript.md](applescript.md), [swift-scripting.md](swift-scripting.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
