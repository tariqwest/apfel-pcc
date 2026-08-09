# WWDC 2026 on-device AI - what it means for apfel-plus

> Knowledge page. Last researched 2026-06-09 against Apple's docs:
> [developer.apple.com/documentation/updates/foundationmodels](https://developer.apple.com/documentation/updates/foundationmodels)
> (FoundationModels OS 27 updates) and
> [developer.apple.com/documentation/coreai](https://developer.apple.com/documentation/coreai/) (Core AI, beta).
> Tracking epic: [#189](https://github.com/Arthur-Ficial/apfel/issues/189).
> Updated 2026-07-22: OS 27 on-device context window confirmed as 8192 on real hardware (#192).

## TL;DR

<<<<<<< HEAD
WWDC 2026 surfaced two things. **The one that matters for apfel-plus is the FoundationModels OS 27
update** - not the "Core AI" rename, which is a non-event for apfel-plus core.
=======
WWDC 2026 surfaced three things. **The one that matters most for apfel is new: Apple shipped a
first-party `fm` CLI** (`fm respond`, `fm chat`, and `fm serve` - "a Chat Completions API server")
that directly overlaps apfel's two core products. Second is the **FoundationModels OS 27 update**
(new on-device model, bigger context, new APIs). The "Core AI" rename is a non-event for apfel core.
>>>>>>> upstream/main

**The real story: FoundationModels gets a substantial OS 27 update.** apfel-plus is built on
FoundationModels (`LanguageModelSession`, `SystemLanguageModel`), and Apple's official updates page
confirms (not press speculation):

- A **new on-device model** (reportedly Gemini-distilled) - Apple says *"test your prompts with the
  new model."* apfel-plus must re-qualify on OS 27 (#193).
- A new **`LanguageModel` protocol** plus open-source **`CoreAILanguageModel`/`MLXLanguageModel`** -
  an official bridge to drive any model through the FoundationModels session API. This makes a
  bring-your-own-model path tractable (#195).
<<<<<<< HEAD
- **`ToolCallingMode`** and **improved error types** - adoption candidates for apfel-plus (#197).
- **On-device context window still reads 4096**; the bigger window is the cloud
  `PrivateCloudComputeLanguageModel`, which apfel-plus does not use - so apfel-plus's 4096 docs likely stand (#192).
=======
- **`ToolCallingMode`** and **improved error types** - adoption candidates for apfel (#197).
- **On-device context window DOUBLED from 4096 to 8192 on OS 27 - CONFIRMED on real hardware**
  (M3 Pro, macOS 27, via `apfel --model-info` and `apfel --count-tokens`). apfel already handles it
  correctly because it reads `SystemLanguageModel.contextSize` at runtime. The hardcoded "4096" doc
  references have been rewritten to describe the dynamic window (#192). See item #1 below.
>>>>>>> upstream/main

**The non-event: "Core AI" is just the Core ML successor.** It is a low-level tensor inference runtime
(`AIModel`/`NDArray`/`InferenceFunction`), **not** a replacement for FoundationModels, with no chat,
prompts, tool calling, or server surface. apfel-plus needs **no Core AI code** and **no migration**. Core AI
only matters as the runtime behind the new `CoreAILanguageModel` bridge above. The rest of this page
explains exactly what Core AI is and is not, so the recurring "why doesn't apfel-plus use Core AI?" question
is answered once.

## The headline for apfel: Apple shipped `fm`

> Researched 2026-06-09. Source: WWDC26 session
> [What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
> and the public `fm --help` capture
> ([gist](https://gist.github.com/robgough/7893602895e75801174750761988ffca)).

macOS 27 ships a **first-party `fm` command-line tool**. Its surface is nearly one-to-one with apfel:

| `fm` subcommand | apfel equivalent |
|---|---|
| `fm respond '...'` (+ `--stream`) | `apfel "prompt"` / `--stream` (core product #1) |
| `fm serve` - *"Start a Chat Completions API server"* | `apfel --serve` (core product #2) |
| `fm chat --instructions '...'` | `apfel --chat` (byproduct #3) |
| `fm token-count '...'` | apfel `TokenCounter` |
| `fm schema object --name Person --string name --int age` | apfel `SchemaConverter` |
| `fm available` | apfel availability checks |
| `fm quota-usage` | (no apfel equivalent - PCC quota) |

Models: `system` (on-device, default) and `pcc` (Private Cloud Compute). Alongside `fm`, Apple shipped
a **Python SDK** (`pip install apple-fm-sdk`, repo `apple/python-apple-fm-sdk`, macOS-only / Apple
Silicon + Apple Intelligence), **open-sourced the core framework** ("runs wherever Swift runs,
including Linux servers"), and a **framework utilities package** whose building blocks include
"chat-completions interfacing (OpenAI-compatible)" - i.e. an official answer to apfel product #2.

**This is the most consequential WWDC item for apfel and it is not Core AI.** Honest read:

- apfel's three user-facing modes (CLI, OpenAI-compatible server, chat) now all have a first-party
  equivalent. The Swift library (#4) is also undercut by the open-sourced framework + utilities
  package + Python SDK.
- Remaining apfel differentiators worth pressing: **available today on macOS 26** (`fm` needs
  macOS 27, so there is an adoption-window lead); **OpenAI-compat depth and maturity** (honest 501s,
  CORS, tool calling, `response_format`, real conformance tests vs. a brand-new `fm serve`);
  **MCP client** (no MCP client surface visible in `fm`); **UNIX ergonomics** (`--json`, `NO_COLOR`,
  exit codes, stdin detection); **cross-channel install** (brew/nix) and the apfel-family ecosystem.
- **Open question for triage:** is `fm serve` genuinely OpenAI-conformant (the exact question asked
  under Franz's HN post)? Worth running apfel's own `openapi_conformance` suite against `fm serve` on
  OS 27 hardware to know precisely where apfel is ahead.

Action: this needs a deliberate positioning decision (README + landing page) and a tracking issue.
Not started here - flagged for Franz.

## What Core AI actually is

From the framework overview (quoted from the docs):

> "Core AI helps you build, run, and deploy AI models in your app. Designed with Apple silicon
> in mind, Core AI allows your app to use the latest model architectures and inference techniques
> across the CPU, GPU, and Neural Engine."

Tagline: *"Run AI models in your app on Apple silicon."*

Core AI is a low-level inference runtime. Its currency is tensors and named inference functions,
not conversations. The mental model:

1. You convert a model (e.g. from PyTorch via the **Core AI PyTorch Extensions** package) into an
   `.aimodel` file, or ahead-of-time compile it to `.aimodelc` with `xcrun coreai-build`.
2. You load and **specialize** it for the current device (`AIModel.specialize(...)`), choosing a
   preferred compute unit (`.cpu`, `.gpu`, `.neuralEngine`) and a cache policy.
3. You run inference functions on `NDArray` tensors or `CVMutablePixelBuffer` images
   (`InferenceFunction.run(inputs:...)`), synchronously or streamed via `ComputeStream`.

Key symbols: `AIModel`, `AIModelAsset`, `InferenceFunction`, `InferenceFunctionDescriptor`,
`InferenceValue`, `NDArray`, `NDArrayDescriptor`, `ComputeStream`, `ComputeUnitKind`,
`SpecializationOptions`, `AIModelCache`, `ImageDescriptor`, `AssetError`. Import is `import CoreAI`.

**Availability:** iOS / iPadOS / macOS / tvOS / visionOS / watchOS **27.0+, all Beta.** Announced at
WWDC 2026 (keynote 2026-06-08), shipping with the iOS 27 / macOS 27 generation. Building
`.aimodel` files needs the Xcode **Metal Toolchain** component.

## What Core AI is NOT

| Misconception | Reality |
|---|---|
| "Core AI replaces FoundationModels" | No. Different framework, different layer. FoundationModels is the developer-facing LLM API; Core AI is the Core ML successor (generic inference). |
| "apfel-plus must migrate to Core AI" | No. There is nothing to migrate. apfel-plus needs LLM sessions/prompts/tools, which Core AI does not provide. |
| "Core AI adds tool calling / structured output / embeddings" | No. None of these exist in Core AI. Those live in FoundationModels (and apfel-plus's own out-of-band tool layer). |
| "Core AI deprecates FoundationModels" | No. FoundationModels is untouched by the Core AI announcement. Core ML continues in compatibility mode. |
| "Core AI gives apfel-plus a new OpenAI-compatible server" | No. Core AI is purely on-device inference. No HTTP, no OpenAI compat, no MCP, no agents. |

## Where apfel-plus sits in Apple's AI stack

```
apfel-plus  (CLI + OpenAI-compatible server + chat)
  └─ FoundationModels      ← apfel-plus is built ENTIRELY on this
       (on-device LLM: sessions, prompts, guided generation, tool support, tokenCount)
  └─ Core AI               ← the Core ML successor; apfel-plus does NOT use this today
       (tensor inference runtime: AIModel / NDArray / InferenceFunction)
  └─ Apple silicon (CPU / GPU / Neural Engine)
```

FoundationModels is almost certainly implemented on top of the same runtime layer Core AI now
exposes, but apfel-plus only ever talks to FoundationModels. Core AI is the layer below the line apfel-plus
draws.

## Direct impact on apfel-plus: effectively none

- **CLI tool** (`apfel-plus "prompt"`): unaffected.
- **OpenAI-compatible server** (`apfel-plus --serve`): unaffected. Core AI has no server or
  OpenAI-compatible concept to align with.
- **Chat / MCP / tool calling**: unaffected.
- **ApfelCore library**: unaffected. It is FoundationModels-free pure Swift; Core AI adds nothing
  it needs to model.
- **TokenCounter** (`SystemLanguageModel.tokenCount(for:)`, SDK 26.4+): a FoundationModels API,
  not a Core AI one. No change from the Core AI announcement.

The golden goal (UNIX tool + OpenAI-compatible server, on FoundationModels, 100% on-device) is
intact.

## Indirect / adjacent items worth tracking

These are the things that actually matter for apfel-plus from the WWDC 2026 / OS 27 cycle. None are
Core AI per se, but they ship in the same window and Core AI is the headline that surfaced them.

> **Update 2026-06-09: these are now confirmed by Apple's official
> [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
> page (June 2026 / OS 27 entries), not just press reporting.** Details folded into the items below.

<<<<<<< HEAD
1. **FoundationModels context window - on-device window appears UNCHANGED at 4096.** apfel-plus's docs and
   behavior are built around a hard **4096-token** context (input + output combined). The figure
   appears across `README.md`, `docs/context-strategies.md`, `docs/integrations.md`,
   `docs/openai-api-compatibility.md`, `docs/mcp-calculator.md` and is the basis for the whole
   context-strategy subsystem. The OS 27 updates page still references **4,096 tokens** for the
   on-device model; the "larger context size" Apple advertises is via the new
   `PrivateCloudComputeLanguageModel` (a **cloud** path apfel-plus deliberately does not use). So apfel-plus's
   on-device 4096 assumption most likely **holds** on OS 27. Still confirm the real number on OS 27
   hardware via `SystemLanguageModel.contextSize` (the API added in 26.4 that removes the hardcode).
=======
1. **FoundationModels context window - on-device window DOUBLED to 8192 on OS 27 (CONFIRMED).**
   **Confirmed 2026-07-22 on real hardware (M3 Pro, macOS 27):** `apfel --model-info` reports
   `context: 8192 tokens` and `apfel --count-tokens` budgets against the same value; the same
   commands report 4096 on macOS 26. This matches the WWDC26 session-241
   ([video](https://developer.apple.com/videos/play/wwdc2026/241/)) example, which prints
   `let model = SystemLanguageModel(); print(model.contextSize) // 8192` for the **on-device** model.
   So: **4096 tokens on macOS 26, 8192 on macOS 27.** The 32K figure is separate again - that is the
   cloud `PrivateCloudComputeLanguageModel`, which apfel does not use.
   - **Behavior was always safe:** apfel reads the live value via `SystemLanguageModel.contextSize`
     (`Sources/TokenCounter.swift` -> `CLI.swift`, `Server.swift`, `Benchmark.swift`), not a
     hardcode. No code change needed for the doubling.
   - **Docs are fixed (#192):** the hardcoded "4096" references across `README.md` and `docs/` now
     describe the dynamic window ("4096 tokens on macOS 26, 8192 on macOS 27") and point at
     `apfel --model-info` for the live value.
>>>>>>> upstream/main

2. **FoundationModels base model change - CONFIRMED.** Apple's updates page states verbatim: *"the
   model changes when a person updates to iOS 27, iPadOS 27, macOS 27, and visionOS 27, test your
   prompts with the new model to verify your app's behavior."* (The new on-device model is reported to
   be distilled from Google Gemini under a multi-year Apple/Google deal.) apfel-plus inherits any change in
   tool-call formatting, refusal behavior, tokenization, or token counts. These are exactly the
   surfaces apfel-plus's recent bug fixes (#176-#183, #187) hardened, so re-qualification on OS 27 hardware
   is required, not optional.

3. **New FoundationModels APIs in OS 27 that touch apfel-plus.** The June 2026 updates also add:
   `GenerationOptions.ToolCallingMode` (control how the model interacts with tools - relevant to
   apfel-plus's out-of-band tool layer); improved error types `LanguageModelError`,
   `SystemLanguageModel.Error`, `LanguageModelSession.Error` (relevant to `ApfelError.classify` and
   parked ticket #119); a `DynamicProfile` agentic API; and image analysis (`OCRTool`,
   `BarcodeReaderTool`). apfel-plus should evaluate whether to adopt `ToolCallingMode` and the new error
   types; the rest (image, agentic, cloud) are out of scope for apfel-plus's golden goal.

4. **macOS 27 build + runtime compatibility.** apfel-plus pins `platforms: [.macOS(.v26)]`. We need to
   confirm: apfel-plus builds against the OS 27 SDK, FoundationModels availability gates still hold,
   `SystemLanguageModel.tokenCount` and `GenerationOptions` are unchanged, and the test suite is
   green on an OS 27 machine. The "macOS 26 Tahoe required" gotcha messaging may need a note.

5. **User confusion ("why doesn't apfel-plus use Core AI?").** Once Core AI is in the press, expect
   issues asking why apfel-plus is not "on Core AI", or requests to run third-party models. We should
   have a one-paragraph canned answer (this page) so triage is fast and consistent.

## Opportunity: bring-your-own-model (future, likely a sister tool)

> **Update 2026-06-09: there is now an official Core AI <-> FoundationModels bridge.** The June 2026
> FoundationModels updates add a `LanguageModel` protocol - *"Adopt the LanguageModel protocol to use
> any large language model - server or on-device"* - plus open-source `CoreAILanguageModel` and
> `MLXLanguageModel` backends. That means a Core AI `.aimodel` (or an MLX model) can be driven through
> the **existing** FoundationModels session API (prompts, tool calling, structured generation) instead
> of reimplementing that stack from scratch. This is materially easier than my first read below, and
> it changes the spike from "build an LLM server on raw tensors" to "wire a `CoreAILanguageModel` into
> a `LanguageModel`-backed session and serve it." Still a separate project, but a much shorter one.

Core AI's genuinely new capability is running **non-Apple model weights** on Apple silicon from an
`.aimodel` file, with explicit compute-unit and caching control. With the new bridge it is more
tractable, but it is still a different project from apfel-plus core:

- It would mean shipping/loading model weights (apfel-plus today downloads nothing - "no downloads" is a
  selling point).
- The hard parts (tokenizer, sampling, KV cache, chat templating) are largely handled if you go
  through `LanguageModel` + `CoreAILanguageModel`, rather than calling `InferenceFunction.run` on raw
  `NDArray`s yourself. The spike should confirm exactly how much the bridge gives you for free.
- It fits the apfel-plus-family pattern (apfel-plus-tag, apfel-plus-spot, apfel-plus-mcp, apfel-plus-server-kit) far better
  than apfel-plus core. If pursued, it should be a **separate repo** (working name e.g. `apfel-plus-coreai` or
  `aimodel-serve`), evaluated with a research spike first.

Recommendation: **do not** put Core AI into apfel-plus core. Track it, write a spike against the
`LanguageModel`/`CoreAILanguageModel` bridge, decide later.

## Decision / recommendation

1. **No code changes to apfel-plus for Core AI itself.** Nothing to do.
2. **Add this page + a short README/FAQ pointer** so the positioning is clear and triage is fast.
3. **Open a tracking epic** covering the adjacent OS 27 / FoundationModels items above, gated on real
   OS 27 hardware availability.
4. **Park the bring-your-own-model idea** as a research spike for a possible sister tool, not apfel-plus
   core.

## Sources

Primary (live beta JSON docs, fetched 2026-06-09):

- [developer.apple.com/documentation/coreai](https://developer.apple.com/documentation/coreai/) - framework root
- `coreai/integrating-on-device-ai-models-in-your-app-with-core-ai` - getting-started article
- `coreai/aimodel`, `coreai/aimodelasset`, `coreai/inferencefunction`, `coreai/inferencevalue`,
  `coreai/ndarray`, `coreai/computestream`, `coreai/computeunitkind`, `coreai/specializationoptions`,
  `coreai/aimodelcache` - symbol references
- `coreai/managing-model-specialization-and-caching`, `coreai/compiling-core-ai-models-ahead-of-time` - articles

FoundationModels OS 27 updates (official, fetched 2026-06-09):

- [developer.apple.com/documentation/updates/foundationmodels](https://developer.apple.com/documentation/updates/foundationmodels) -
  June 2026 entries: updated on-device `SystemLanguageModel` ("the model changes when a person updates
  to ... 27"), `LanguageModel` protocol, open-source `CoreAILanguageModel` / `MLXLanguageModel`,
  `GenerationOptions.ToolCallingMode`, improved error types, `DynamicProfile`, image analysis,
  `PrivateCloudComputeLanguageModel` (cloud, larger context).
<<<<<<< HEAD
- The on-device context window still reads **4,096 tokens** on this page; the larger context is the
  cloud `PrivateCloudComputeLanguageModel`, which apfel-plus does not use.
=======
- The on-device context window is **4,096 tokens on macOS 26** and **8,192 tokens on macOS 27** -
  confirmed on real macOS 27 hardware via `apfel --model-info` and `apfel --count-tokens` (see
  item #1 above). The 32K+ figure is separate again - that is the cloud
  `PrivateCloudComputeLanguageModel`, which apfel does not use.
>>>>>>> upstream/main

Context / reporting: WWDC 2026 keynote coverage (2026-06-08) on the Core ML to Core AI rename, the
FoundationModels coexistence story, and the Apple/Google Gemini base-model collaboration. The
on-device base-model change and the new APIs above are confirmed by Apple's updates page; the
on-device context window has since been confirmed on OS 27 hardware (8192 tokens) and is always read
at runtime via `SystemLanguageModel.contextSize` rather than hardcoded.
