# Context Strategies

<<<<<<< HEAD
apfel-plus manages the 4096-token context window automatically so chat sessions and long prompts do not crash. Choose a strategy with `--context-strategy` based on what you want apfel-plus to keep when history approaches the limit.
=======
apfel manages the on-device context window (4096 tokens on macOS 26, 8192 on macOS 27 - read at runtime via `SystemLanguageModel.contextSize`) automatically so chat sessions and long prompts do not crash. Choose a strategy with `--context-strategy` based on what you want apfel to keep when history approaches the limit.
>>>>>>> upstream/main

```bash
apfel-plus --chat --context-strategy newest-first     # default: keep recent turns
apfel-plus --chat --context-strategy oldest-first     # keep earliest turns
apfel-plus --chat --context-strategy sliding-window --context-max-turns 6
apfel-plus --chat --context-strategy summarize        # compress old turns via on-device model
apfel-plus --chat --context-strategy strict           # error on overflow, no trimming
apfel-plus --chat --context-output-reserve 256        # custom output token reserve
apfel-plus --chat --context-status                    # print context fill after each turn
```

## Strategies

| Strategy | What it keeps | When to use |
|---|---|---|
| `newest-first` (default) | Most recent turns. Old turns are dropped when the window fills. | Normal chat. You want the model to remember what you just said. |
| `oldest-first` | Earliest turns. New turns are dropped when the window fills. | Instructions or context at the start of a session that must never fall out. |
| `sliding-window` | A rolling window of the last N turns (`--context-max-turns N`). | Predictable memory usage, simple last-N-turns semantics. |
| `summarize` | Old turns compressed into a short summary by the on-device model, then appended as context. | Long sessions where you want continuity without losing old content entirely. Costs one extra on-device inference per rotation. |
| `strict` | Everything. Errors with `contextOverflow` when the window fills. | CI, scripts, batch pipelines - fail loud instead of silently dropping content. |

## Output token reserve

`--context-output-reserve N` (default `512`) reserves `N` tokens of the window for the model's response. The remaining `4096 - N` tokens are available for input + history (4096 is the macOS 26 window, read dynamically at runtime; on macOS 27 it is `8192 - N`). Lower the reserve if your prompts are long and your answers are short, raise it if answers get cut off.

## Context status

`--context-status` prints the current chat context fill after each turn, for example `[context 2381/3584 tokens, 66%, 1203 remaining]`. It uses the same token count and input budget that apfel-plus already checks before rotating context.

## Environment variables

These settings have env var equivalents:

- `APFEL_CONTEXT_STRATEGY` - one of `newest-first`, `oldest-first`, `sliding-window`, `summarize`, `strict`
- `APFEL_CONTEXT_MAX_TURNS` - positive integer for sliding-window
- `APFEL_CONTEXT_OUTPUT_RESERVE` - positive integer, tokens reserved for output

CLI flags always override env vars.
