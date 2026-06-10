# How to use the Apple Foundation Model from AppleScript

Call Apple's on-device Foundation Model from AppleScript via `do shell script` + `curl`. 100% on-device - perfect for Shortcuts, Automator, and macOS system automation.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/applescript](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/applescript).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus jq`
- `apfel-plus --serve` running (port `11434`)
- AppleScript (ships with macOS)

AppleScript has no native HTTP client; the idiomatic pattern is `do shell script "curl ..."`.

## 1. One-shot

```applescript
set payload to "{\"model\":\"apple-foundationmodel\",\"messages\":[{\"role\":\"user\",\"content\":\"In one sentence, what is the Swift programming language?\"}],\"max_tokens\":80}"
set response to do shell script "curl -sS http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' -d " & quoted form of payload & " | jq -r '.choices[0].message.content'"
return response
```

Real output:

```text
Swift is a modern, open-source programming language developed by Apple for developing iOS, macOS, watchOS, and tvOS applications.
```

Lab script: [`01_oneshot.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/01_oneshot.applescript).

## 2. Streaming

AppleScript doesn't stream natively - `do shell script` returns the final string only. Streaming happens inside the shell pipeline:

```applescript
set shellCmd to "curl -sS -N http://localhost:11434/v1/chat/completions " & ¬
    "-H 'Content-Type: application/json' " & ¬
    "-d '{\"model\":\"apple-foundationmodel\",\"messages\":[{\"role\":\"user\",\"content\":\"List three Apple silicon chips, one per line.\"}],\"max_tokens\":80,\"stream\":true}' " & ¬
    "| while IFS= read -r line; do " & ¬
    "    line=\"${line#data: }\"; " & ¬
    "    [ -z \"$line\" ] || [ \"$line\" = \"[DONE]\" ] && continue; " & ¬
    "    content=$(printf '%s' \"$line\" | jq -r '.choices[0].delta.content // empty' 2>/dev/null || true); " & ¬
    "    [ -n \"$content\" ] && printf '%s' \"$content\"; " & ¬
    "  done; echo"
return do shell script shellCmd
```

Real output:

```text
Apple M1  
Apple M1 Pro  
Apple M1 Max
```

Lab script: [`02_stream.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/02_stream.applescript).

## 3. JSON mode

```applescript
set payload to "{\"model\":\"apple-foundationmodel\",\"messages\":[{\"role\":\"user\",\"content\":\"Return JSON with fields chip, year, cores. Describe the Apple M1 chip. Return ONLY JSON.\"}],\"response_format\":{\"type\":\"json_object\"},\"max_tokens\":120}"
set cmd to "curl -sS http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' -d " & quoted form of payload & " | jq -r '.choices[0].message.content' | sed -E 's/^```(json)?//; s/```$//' | tr -d '\\r' | jq '.'"
return do shell script cmd
```

Real output (note AppleScript collapses newlines when returning from `do shell script`):

```json
{  "chip": "Apple M1",  "year": 2020,  "cores": 8}
```

Lab script: [`03_json.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/03_json.applescript).

## 4. Error handling

```applescript
set cmd to "tmp=$(mktemp); status=$(curl -sS -o \"$tmp\" -w '%{http_code}' http://localhost:11434/v1/embeddings -H 'Content-Type: application/json' -d '{\"model\":\"apple-foundationmodel\",\"input\":\"apfel-plus runs 100% on-device.\"}'); if [ \"$status\" -ge 400 ]; then msg=$(jq -r '.error.message // empty' \"$tmp\" 2>/dev/null || true); echo \"Got expected error: HTTP $status - ${msg:-see response}\"; else echo \"unexpected success: HTTP $status\"; cat \"$tmp\"; fi; rm -f \"$tmp\""
return do shell script cmd
```

Real output:

```text
Got expected error: HTTP 501 - Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/04_errors.applescript).

## 5. Tool calling (delegate to Bash)

Tool calling from pure AppleScript is not idiomatic - the required JSON escaping becomes unreadable fast. The correct AppleScript pattern is to delegate complex shell work to a script file. Reuse the Bash tool-calling script:

```applescript
set scriptPath to POSIX path of ((path to me as text) & "::") & "../bash-curl/05_tools.sh"
return do shell script "bash " & quoted form of scriptPath
```

Real output:

```text
The current temperature in Vienna is 14 degrees Celsius.
```

Lab script: [`05_tools.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/05_tools.applescript). For production tool-calling, use [python.md](python.md) or [nodejs.md](nodejs.md).

## 6. Real example - summarize a file

AppleScript cannot read stdin inside `do shell script`, so pass a file path on argv:

```applescript
on run argv
  if (count of argv) < 1 then error "usage: osascript 06_example.applescript <path-to-file>"
  set filePath to item 1 of argv
  set cmd to "text=$(cat " & quoted form of filePath & "); " & ¬
    "payload=$(jq -n --arg text \"$text\" '{model:\"apple-foundationmodel\", messages:[{role:\"system\",content:\"You are a concise summarizer. Reply with one short paragraph.\"},{role:\"user\",content:(\"Summarize:\\n\\n\" + $text)}], max_tokens:150}'); " & ¬
    "curl -sS http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' -d \"$payload\" | jq -r '.choices[0].message.content'"
  return do shell script cmd
end run
```

Usage: `osascript 06_example.applescript /path/to/file.txt`

Real output:

```text
In November 2020, Apple released the M1 chip, the first ARM-based system-on-a-chip for Mac computers. The chip features an 8-core CPU with four performance and four efficiency cores, an integrated GPU with up to 8 cores, and a unified CPU, GPU, memory, and neural engine on a single die. The M1 chip offers significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.applescript`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/applescript/06_example.applescript).

## Shortcuts integration

Paste any of these into a **Run AppleScript** action in Shortcuts. Combine with **Get Contents of Clipboard** to summarize whatever you just copied - all on-device, no network call.

## Troubleshooting

- **Collapsed newlines** - `do shell script` returns a single AppleScript string with all newlines folded. That's a Classic macOS quirk, not an apfel-plus issue.
- **Stdin not flowing** - AppleScript cannot pipe its own stdin into `do shell script`. Pass file paths via `on run argv` instead.
- **Escaping** - always use `quoted form of` for any user-supplied string before embedding in a shell command.

## Tested with

- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
- osascript / AppleScript (system) / jq 1.7
- Date: 2026-04-16

Runnable tests: [tests/test_applescript.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_applescript.py).

## See also

[bash-curl.md](bash-curl.md), [zsh.md](zsh.md), [swift-scripting.md](swift-scripting.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
