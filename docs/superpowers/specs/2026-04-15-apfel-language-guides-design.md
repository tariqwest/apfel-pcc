# Design - apfel-plus language guides

**Date:** 2026-04-15
**Status:** Approved (brainstorming phase)
**Next step:** writing-plans skill -> implementation plan

## Goal

Ship a set of SEO-optimized, empirically tested "how to use the Apple Foundation Model from `<language>`" guides in the apfel-plus repo, backed by a separate lab repo that holds the runnable scripts and pytest harness that prove every code block actually works against a live `apfel-plus --serve`.

## Scope

**In scope - 10 scripting-language guides (v1):**

Tier 1 (highest search volume):
1. Python
2. PHP
3. Ruby
4. Node.js (JavaScript/TypeScript)
5. Bash / curl

Tier 2 (Mac-native / Mac-shipped scripting):
6. AppleScript
7. Swift scripting (`swift-sh` / shebang)
8. Zsh (distinct from Bash - default macOS shell)
9. Perl (ships with macOS)
10. AWK (ships with macOS)

**Out of scope (YAGNI):**
- Tier 3 niche scripting (Lua, Tcl, R, Elixir, Groovy, Raku)
- Compiled languages (Go, Rust, Java, C#, Kotlin)
- Framework-specific guides (Django, Rails, Laravel, Next.js)
- Docker / devcontainer setups
- Video or interactive playground
- Translations (English only v1)

## Two repositories

### `Arthur-Ficial/apfel` (this repo) - docs only

New directory: `docs/guides/`

```
docs/guides/
├── index.md               # Hub landing page, SEO-tuned
├── python.md
├── php.md
├── ruby.md
├── nodejs.md
├── bash-curl.md
├── applescript.md
├── swift-scripting.md
├── zsh.md
├── perl.md
└── awk.md
```

Linked from:
- `README.md` (new "Using from other languages" section)
- `docs/integrations.md` (cross-link)

### `Arthur-Ficial/apfel-guides-lab` (new repo) - runnable proof

```
apfel-guides-lab/
├── README.md                   # "This is the lab; apfel-plus docs are in the main repo"
├── Makefile                    # make test, make capture, make test-<lang>
├── conftest.py                 # pytest: boots `apfel-plus --serve` on :11434, waits /health
├── pyproject.toml              # pytest + tooling
├── scripts/
│   ├── python/
│   │   ├── 01_oneshot.py
│   │   ├── 02_stream.py
│   │   ├── 03_json.py
│   │   ├── 04_errors.py
│   │   ├── 05_tools.py
│   │   └── 06_example.py
│   ├── php/                    # same 6 files, .php
│   ├── ruby/                   # same 6 files, .rb
│   ├── nodejs/                 # same 6 files, .mjs
│   ├── bash-curl/              # same 6 files, .sh
│   ├── applescript/            # same 6 files, .applescript (tools=N/A)
│   ├── swift-scripting/        # same 6 files, .swift
│   ├── zsh/                    # same 6 files, .zsh
│   ├── perl/                   # same 6 files, .pl (tools=N/A)
│   └── awk/                    # same 6 files, .awk (tools=N/A, json best-effort)
├── tests/
│   ├── test_python.py
│   ├── test_php.py
│   ├── test_ruby.py
│   ├── test_nodejs.py
│   ├── test_bash_curl.py
│   ├── test_applescript.py
│   ├── test_swift_scripting.py
│   ├── test_zsh.py
│   ├── test_perl.py
│   └── test_awk.py
└── outputs/                    # committed real stdout captures
    ├── python/
    │   ├── 01_oneshot.txt
    │   └── ...
    └── <each lang>/
```

## Per-guide structure (identical skeleton, SEO-tuned)

Every `docs/guides/<lang>.md` follows the same sections:

1. **H1**: `How to use the Apple Foundation Model from <Language>` - exact-match SEO headline
2. **Intro** - what apfel-plus is, why 100% on-device matters, what this guide covers (~3 sentences)
3. **Prerequisites** - macOS 26+, Apple Silicon, Apple Intelligence enabled, `brew install apfel-plus`, `apfel-plus --serve` running
4. **One-shot chat completion** - minimal working code + real captured output
5. **Streaming** - idiomatic streaming code + real captured output
6. **JSON mode / structured output** - `response_format: {"type": "json_object"}` + parsed result
7. **Error handling** - trigger a known 501 or timeout, show how to catch cleanly
8. **Tool calling** - where supported (Python, Node.js, PHP, Ruby via OpenAI SDKs). For AppleScript/AWK/Zsh/Bash/Perl/Swift: explicitly state "raw HTTP only - use Python or Node.js if you need tool-calling," then show a minimal raw JSON POST as proof of capability
9. **Real mini-example** - "summarize a file from stdin," idiomatic to the language
10. **Troubleshooting** - 3-5 common errors (server not running, Apple Intelligence disabled, wrong port, JSON parse errors)
11. **Tested with** - `apfel-plus <version>`, macOS <version>, `<language> <version>`, date. Link to the exact script in the lab repo at a pinned commit SHA

## Lab repo harness

- **pytest** with `conftest.py` session-scoped fixture that:
  1. Verifies `apfel-plus` is on PATH (skip with clear message if not)
  2. Boots `apfel-plus --serve --port 11434` as a background subprocess
  3. Polls `/health` until 200 (or fails with timeout)
  4. Yields to tests
  5. Sends `SIGTERM` on teardown; `SIGKILL` if it lingers
- **One `test_<lang>.py` per language**, parametrized over the script files in that language's directory
- **Each test** does `subprocess.run(script, capture_output=True, timeout=60)`:
  - asserts exit code 0
  - asserts stdout is non-empty
  - asserts loose regex match (model output varies; no brittle exact-match assertions)
- **`make capture`** re-runs every script against the live server and writes `outputs/<lang>/<script>.txt`. These are the snippets pasted into the published guides.

## Dependencies (lab repo)

Pinned per-language, installed via native package managers:

| Language | Package mgr | Library |
|----------|-------------|---------|
| Python | `uv` | `openai` |
| PHP | `composer` | `openai-php/client` |
| Ruby | `bundler` | `ruby-openai` |
| Node.js | `npm` | `openai` |
| Swift scripting | `swift-sh` | native `URLSession` |
| AppleScript | (none) | `curl` via `do shell script` |
| Zsh | (none) | `curl` |
| Bash | (none) | `curl` |
| Perl | (system) | `LWP::UserAgent` or `curl` |
| AWK | (none) | `curl` piped |

A `Brewfile` at the repo root installs any brew-available toolchains; per-language lockfiles (`requirements.txt`, `composer.lock`, `Gemfile.lock`, `package-lock.json`) pin client library versions.

## CI

- **`apfel-guides-lab` GitHub Actions**: runs on push. Most tests skip on CI (GitHub runners lack Apple Intelligence) - uses the same honest-skip pattern as apfel-plus integration tests. Real qualification is `make test` locally on the Mac before publishing any guide update.
- **`apfel-plus` repo**: no CI change. Guides are pure Markdown.

## Workflow per language (for me, Arthur, to follow during build-out)

1. Write script in `apfel-guides-lab/scripts/<lang>/`
2. `make test-<lang>` against a running `apfel-plus --serve` - must pass, empirically
3. `make capture` - real stdout lands in `outputs/<lang>/`
4. Write `docs/guides/<lang>.md` in apfel-plus repo, paste the real output
5. Commit both repos. Link from the guide to the exact lab-repo commit SHA (immutable proof)

## SEO notes

- H1 on every guide: exact-match phrase `How to use the Apple Foundation Model from <Language>`
- Hub page (`docs/guides/index.md`): target `use Apple Foundation Model from any language`, `local LLM scripting Mac`, `on-device AI <language>`
- Each guide includes a meta-style opening paragraph with keyword density (Apple Foundation Model, on-device, Mac, `<Language>`)
- All guides cross-link to each other at the bottom ("See also: <other-lang>")
- All guides link to `docs/openai-api-compatibility.md` and `docs/install.md` on apfel-plus repo

## Versioning and maintenance

- Each guide's "Tested with" footer names exact apfel-plus + language runtime + macOS versions + date
- When apfel-plus releases a version with API-affecting changes, re-run `make test && make capture` in the lab, update the guides' footers and any output that changed
- Lab repo commit SHA pinned in every guide - if a future reader wants the exact code that produced the output, they follow that link

## Bug reporting (apfel-plus itself)

Empirical testing across 10 languages will exercise apfel-plus's OpenAI surface harder than any prior integration test. Expected outcome: some bugs surface (wrong status codes, header-case mismatches, streaming edge cases, JSON-mode quirks with certain prompt shapes, CORS issues, etc.).

**Rule:** whenever testing a script reveals a bug, inconsistency, or spec violation in apfel-plus (not in the guide script), file a GitHub issue on `Arthur-Ficial/apfel` before moving on. The issue must include:

- Failing language + script path (lab repo, pinned commit SHA)
- The exact request sent (curl reproducer)
- Observed response vs. expected response
- apfel-plus version

Do not work around apfel-plus bugs in the guide scripts. If a language exposes a real apfel-plus bug, file the ticket, mark the guide section as "Blocked on apfel-plus#<N>" in the lab repo, and move to the next section. The guide gets published only after the ticket is resolved in apfel-plus and re-verified.

## Success criteria

- All 10 guides present in `docs/guides/` and linked from README
- All 10 language directories in the lab repo with 6 scripts each
- `make test` in the lab repo passes on Arthur's Mac, 0 skipped (when `apfel-plus --serve` is up)
- Every code block in every guide matches the real captured output byte-for-byte
- Lab repo README clearly explains its purpose and relationship to apfel-plus
- README.md on apfel-plus repo has a discoverable link to `docs/guides/index.md`
