# apfel-plus Language Guides Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship 10 SEO-optimized, empirically tested guides in `docs/guides/` backed by a new `apfel-guides-lab` repo that holds runnable scripts + pytest harness.

**Architecture:** Two repos. apfel-plus hosts markdown only. apfel-guides-lab hosts scripts + pytest harness that boots `apfel-plus --serve` and proves every script works. Guides paste real captured output.

**Tech Stack:** pytest, uv, composer, bundler, npm, swift-sh, curl, Perl, AWK, AppleScript, Zsh, Bash.

**Spec:** `docs/superpowers/specs/2026-04-15-apfel-plus-language-guides-design.md`

---

## Phase 1 - Lab repo bootstrap

### Task 1: Create apfel-guides-lab repo locally + on GitHub

**Files:**
- Create: `~/dev/apfel-guides-lab/` (new directory, not in apfel-plus repo)

- [ ] Create directory + git init
- [ ] Create GitHub repo `Arthur-Ficial/apfel-guides-lab` via `gh repo create` (public, no README, no license yet)
- [ ] First commit: placeholder README
- [ ] Push to main

### Task 2: Write lab repo README and Makefile

**Files:**
- Create: `~/dev/apfel-guides-lab/README.md`
- Create: `~/dev/apfel-guides-lab/Makefile`

- [ ] README explains purpose, links to apfel-plus repo, explains `make test` / `make capture`
- [ ] Makefile targets: `test`, `test-<lang>` (10 of them), `capture`, `capture-<lang>`, `clean`
- [ ] Commit

### Task 3: Set up pytest harness

**Files:**
- Create: `~/dev/apfel-guides-lab/pyproject.toml`
- Create: `~/dev/apfel-guides-lab/conftest.py`
- Create: `~/dev/apfel-guides-lab/.gitignore`

- [ ] `pyproject.toml` with pytest + requests deps
- [ ] `conftest.py`: session-scoped fixture boots `apfel-plus --serve --port 11434`, polls `/health` until 200, tears down on SIGTERM
- [ ] `.gitignore`: `__pycache__/`, `.venv/`, `node_modules/`, `vendor/`, `.pytest_cache/`, `outputs/*.tmp`
- [ ] Commit

### Task 4: Write generic pytest helpers

**Files:**
- Create: `~/dev/apfel-guides-lab/tests/__init__.py`
- Create: `~/dev/apfel-guides-lab/tests/helpers.py`

- [ ] `run_script(path, stdin=None, timeout=60)` -> `CompletedProcess`
- [ ] `assert_nonempty_model_output(stdout)` - asserts non-empty, non-error
- [ ] `capture_to(path, stdout)` - writes output for snippet reuse
- [ ] Commit

### Task 5: Sanity-check harness

- [ ] Start `apfel-plus --serve` in a separate terminal
- [ ] Write minimal `tests/test_harness.py` that just curls `/health` via subprocess, asserts 200
- [ ] Run `pytest -v` - must pass
- [ ] Commit

---

## Phase 2 - Python (canonical template)

### Task 6: Python 01 - one-shot

**Files:**
- Create: `~/dev/apfel-guides-lab/scripts/python/01_oneshot.py`
- Create: `~/dev/apfel-guides-lab/tests/test_python.py`

- [ ] Write `01_oneshot.py` using `openai` SDK pointed at `http://localhost:11434/v1`, sends a prompt, prints response
- [ ] Write `test_python.py::test_oneshot` that runs the script, asserts non-empty stdout
- [ ] Run test, verify PASS against live server
- [ ] `make capture` -> `outputs/python/01_oneshot.txt`
- [ ] Commit

### Task 7: Python 02 - streaming

- [ ] `02_stream.py` uses `stream=True`, prints chunks as they arrive
- [ ] Add `test_python.py::test_stream` - asserts multiple newlines/chunks in output
- [ ] Run, capture, commit

### Task 8: Python 03 - JSON mode

- [ ] `03_json.py` uses `response_format={"type": "json_object"}`, prompts for structured data, parses via `json.loads`
- [ ] Test: asserts stdout parses as JSON
- [ ] Run, capture, commit

### Task 9: Python 04 - error handling

- [ ] `04_errors.py` intentionally triggers a 501 (call `/v1/embeddings`), catches `openai.APIError` cleanly, prints friendly message
- [ ] Test: asserts exit 0 and error message formatted
- [ ] Run, capture, commit

### Task 10: Python 05 - tool calling

- [ ] `05_tools.py` defines a `get_weather(city)` tool schema, sends prompt, handles tool call, returns fake result, prints final answer
- [ ] Test: asserts final stdout mentions weather/temperature
- [ ] Run, capture, commit
- [ ] **If apfel-plus bug found:** file issue on `Arthur-Ficial/apfel`, mark script as Blocked in a `BLOCKED.md` in lab repo

### Task 11: Python 06 - real mini-example

- [ ] `06_example.py` reads file path from argv, reads file, asks model to summarize, prints summary
- [ ] Test: pipes a known file, asserts summary non-empty
- [ ] Run, capture, commit

---

## Phase 3 - Node.js

Same 6 scripts. Use `openai` npm package. `.mjs` files for ES modules.

- [ ] Task 12: Node 01 oneshot + test + capture + commit
- [ ] Task 13: Node 02 streaming (async iterator)
- [ ] Task 14: Node 03 JSON mode
- [ ] Task 15: Node 04 error handling (`catch (e)` on `OpenAI.APIError`)
- [ ] Task 16: Node 05 tool calling
- [ ] Task 17: Node 06 mini-example (read `process.argv[2]`, summarize)

---

## Phase 4 - Ruby

- [ ] Task 18-23: Ruby 01-06 using `ruby-openai` gem
- [ ] `Gemfile` + `Gemfile.lock` pinned
- [ ] Error handling via `OpenAI::Error` rescue

---

## Phase 5 - PHP

- [ ] Task 24-29: PHP 01-06 using `openai-php/client` via composer
- [ ] `composer.json` + `composer.lock` pinned
- [ ] Error handling via `\OpenAI\Exceptions\ErrorException`

---

## Phase 6 - Bash / curl

- [ ] Task 30-35: Bash 01-06 using `curl` + `jq`
- [ ] Streaming: `curl -N` + line parsing
- [ ] JSON: pipe through `jq`
- [ ] Error: check HTTP status
- [ ] Tools: raw JSON POST, parse tool_calls with `jq`, re-POST with tool result
- [ ] Example: `cat file | bash 06_example.sh`

---

## Phase 7 - Zsh

- [ ] Task 36-41: same as Bash but using Zsh-specific idioms (parameter expansion, `read -A`, globbing)
- [ ] Scripts start with `#!/bin/zsh` explicitly

---

## Phase 8 - AppleScript

- [ ] Task 42-47: AppleScript 01-06 using `do shell script "curl ..."`
- [ ] 05_tools.applescript: document as "not idiomatic - use Python/Node for tool calling" but include working raw curl proof
- [ ] Output parsing via `do shell script` with jq
- [ ] 06_example: read file via Finder scripting or argv

---

## Phase 9 - Swift scripting

- [ ] Task 48-53: Swift 01-06 using `swift-sh` shebang, `URLSession` async/await
- [ ] `import Foundation`, `#if canImport(FoundationNetworking)` for portability
- [ ] Streaming: `URLSession.shared.bytes(for:)`

---

## Phase 10 - Perl

- [ ] Task 54-59: Perl 01-06 using `LWP::UserAgent` + `JSON::PP` (both ship with macOS)
- [ ] Streaming: `LWP::UserAgent::request` with chunked callback
- [ ] 05_tools.pl: document N/A, include raw POST

---

## Phase 11 - AWK

- [ ] Task 60-65: AWK 01-06 - AWK can't do HTTP, so scripts use `curl | awk` pattern
- [ ] Document as "AWK for parsing, curl for transport"
- [ ] 03_json: `awk` regex on JSON (or pipe to `jq` and honest about it)
- [ ] 05_tools.awk: N/A, include raw curl proof
- [ ] 06_example: `awk` pre-processes stdin, pipes to curl

---

## Phase 12 - Guide template + index

### Task 66: Create guide template

**Files:**
- Create: `~/dev/apfel-guides-lab/TEMPLATE.md` (reference for writing guides)

- [ ] Template with all 11 sections from spec
- [ ] Include SEO H1 format, meta-intro, Tested with footer format
- [ ] Commit to lab repo

### Task 67: Write docs/guides/index.md in apfel-plus repo

**Files:**
- Create: `/Users/arthurficial/dev/apfel-plus/docs/guides/index.md`

- [ ] Hub page: one-paragraph intro, table of 10 languages each linking to its guide
- [ ] SEO-tuned title + meta intro
- [ ] Commit to apfel-plus repo

---

## Phase 13 - Per-language guides

One task per language. Each task:
1. Paste captured outputs from lab repo into the guide
2. Follow TEMPLATE.md structure exactly
3. Link to lab repo commit SHA for each script
4. Commit to apfel-plus repo

- [ ] Task 68: `docs/guides/python.md`
- [ ] Task 69: `docs/guides/nodejs.md`
- [ ] Task 70: `docs/guides/ruby.md`
- [ ] Task 71: `docs/guides/php.md`
- [ ] Task 72: `docs/guides/bash-curl.md`
- [ ] Task 73: `docs/guides/zsh.md`
- [ ] Task 74: `docs/guides/applescript.md`
- [ ] Task 75: `docs/guides/swift-scripting.md`
- [ ] Task 76: `docs/guides/perl.md`
- [ ] Task 77: `docs/guides/awk.md`

---

## Phase 14 - Integration

### Task 78: Link guides from README

**Files:**
- Modify: `/Users/arthurficial/dev/apfel-plus/README.md`

- [ ] Add "Using apfel-plus from other languages" section with link to `docs/guides/index.md`
- [ ] Cross-link from `docs/integrations.md`
- [ ] Commit

### Task 79: Final verification

- [ ] `make test` in lab repo: all 60 scripts (10 langs x 6) pass, 0 skipped
- [ ] Every code block in every guide matches its `outputs/<lang>/*.txt` byte-for-byte
- [ ] All "Tested with" footers point to a real lab commit SHA
- [ ] README.md link works

### Task 80: Publish lab repo

- [ ] `gh repo edit Arthur-Ficial/apfel-guides-lab --description "..." --homepage "https://apfel-plus.franzai.com"`
- [ ] Final push

---

## Bug reporting

Per spec: any apfel-plus bug found during testing = GitHub issue on `Arthur-Ficial/apfel` with curl reproducer, version, observed vs expected. Script marked Blocked in lab repo. Guide section held until apfel-plus fix + re-verify.
