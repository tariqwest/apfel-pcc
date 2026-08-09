# apfel-plus Integrations

Community-contributed configurations for using apfel-plus with other tools.

For **scripting language guides** (how to call apfel-plus from Python, Node.js, Ruby, PHP, Bash, Zsh, AppleScript, Swift, Perl, AWK) see [docs/guides/index.md](guides/index.md). Every snippet there was run against a live apfel-plus server; lab repo: [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab).

---

## opencode

<<<<<<< HEAD
[opencode](https://opencode.ai) is an open-source terminal AI coding assistant. You can wire it to apfel-plus's OpenAI-compatible server so all inference stays on-device at zero cost.

**Config:** `~/.config/opencode/opencode.json`

```json
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": true,
  "compaction": {
    "auto": true,
    "prune": true,
    "reserved": 512
  },
  "default_agent": "lean",
  "agent": {
    "lean": {
      "mode": "primary",
      "model": "apfel-plus/apple-foundationmodel",
      "prompt": "You are a concise assistant. Answer directly.",
      "permission": {
        "*": "deny"
      }
    }
  },
  "provider": {
    "apfel-plus": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "apfel-plus",
      "options": {
        "baseURL": "http://127.0.0.1:11434/v1"
      },
      "models": {
        "apple-foundationmodel": {
          "name": "apple-foundationmodel"
        }
      }
    }
  }
}
```

**Start apfel-plus first:**

```bash
apfel-plus --serve
```

**Why this config works the way it does:**

- `default_agent: "lean"` - the lean agent has `"permission": { "*": "deny" }`, which means opencode won't try to inject tool schemas. This matters because apfel-plus has a 4096-token context window - tool schemas eat into it fast.
- `compaction.reserved: 512` - reserves 512 tokens for output. Keeps the model from running out of room mid-answer.
- `"npm": "@ai-sdk/openai-compatible"` - opencode's provider system. This package speaks the OpenAI REST protocol, which apfel-plus implements at `/v1/chat/completions`.
- `baseURL: "http://127.0.0.1:11434/v1"` - apfel-plus's default port and path.

**Result:** $0.00/request, fully on-device, 1-2s response times.

![opencode using apple-foundationmodel via apfel-plus](../screenshots/opencode-integration.png)

*opencode 1.3.17, answering from the `lean` agent backed by `apple-foundationmodel` via apfel-plus. Context: 1,181 tokens, $0.00 spent.*

---

Huge thanks to [**@tvi** (Tomas Virgl)](https://github.com/tvi) for contributing this integration and for taking the time to provide a working config and a real screenshot. This is exactly the kind of community contribution that makes apfel-plus more useful.
=======
[opencode](https://opencode.ai) is an open-source terminal AI coding agent. Wire it to apfel's OpenAI-compatible server and every token stays on-device at zero cost. Re-verified end-to-end on opencode 1.17.16 + apfel 1.8.2.

Full setup, the verified config, a real transcript, and every gotcha are on the dedicated page: [docs/integrations/opencode.md](integrations/opencode.md). The one you must not miss: opencode pastes your global `~/.claude/CLAUDE.md` into the system prompt, which overflows apfel's on-device context window (4096 tokens on macOS 26, 8192 on macOS 27) - fix it with `export OPENCODE_DISABLE_CLAUDE_CODE_PROMPT=1`.
>>>>>>> upstream/main

---

## Zed

[Zed](https://zed.dev)'s agent panel works with apfel-plus via the chat-completions provider. On-device, no key.

**Heads-up:** use `language_models.openai_compatible` (chat). Do **not** use `edit_predictions.open_ai_compatible_api` - that's a legacy text-completions endpoint apfel-plus deliberately doesn't support.

**Config:** `~/.config/zed/settings.json`

```json
{
  "language_models": {
    "openai_compatible": {
      "Apfel": {
        "api_url": "http://127.0.0.1:11434/v1",
        "available_models": [
          {
            "name": "apple-foundationmodel",
            "display_name": "Apfel (apple on-device)",
            "max_tokens": 4096,
            "max_output_tokens": 1024,
            "capabilities": { "tools": true, "images": false, "parallel_tool_calls": false, "prompt_cache_key": false }
          }
        ]
      }
    }
  }
}
```

<<<<<<< HEAD
Start apfel-plus:
=======
`max_tokens: 4096` matches the macOS 26 on-device window; on macOS 27 the window is 8192 - `apfel --model-info` prints the live value.

Start apfel:
>>>>>>> upstream/main

```bash
apfel-plus --serve
```

Launch Zed (Zed insists on a key for the provider; apfel-plus ignores it):

```bash
APFEL_API_KEY=dummy zed
```

Open the agent panel (`Cmd+?`), pick `Apfel (apple on-device)`, send a prompt. Zed POSTs to `/v1/chat/completions` on apfel-plus.

---

## Visual Studio Code + Continue

Use `apfel-plus` as the local review/chat model in Visual Studio Code and pair it with a second model for Edit/Apply. (See also: [Leveraging multiple, repository-specific OpenAI Codex API Keys with Visual Studio Code on macOS](https://snelson.us/2026/04/many-to-one-api-keys/).)

Step-by-step setup: [local-setup-with-vs-code.md](local-setup-with-vs-code.md)

Why this setup works well:

- `apfel-plus` stays in the small-context, low-latency review lane
- Continue provides the Visual Studio Code integration
<<<<<<< HEAD
- a second model can handle larger edit/apply tasks without overloading `apfel-plus`'s 4096-token context window
=======
- a second model can handle larger edit/apply tasks without overloading `apfel`'s small on-device context window (4096 tokens on macOS 26, 8192 on macOS 27)
>>>>>>> upstream/main

---

*Have an integration to share? Open an issue at [https://github.com/Arthur-Ficial/apfel/issues](https://github.com/Arthur-Ficial/apfel/issues).*
