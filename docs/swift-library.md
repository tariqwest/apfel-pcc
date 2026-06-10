# Swift Library: ApfelCore

`ApfelCore` is the pure, FoundationModels-free Swift Package product inside this repo. It exists for Swift developers who want the reusable policy pieces - OpenAI-compatible types, validation, MCP helpers, schema parsing, retry classification, context-trimming strategies - without depending on the `apfel-plus` executable.

**The main product is the `apfel-plus` CLI and the `apfel-plus --serve` OpenAI-compatible server.** The Swift library is a secondary surface for downstream developers. If you just want to talk to Apple's on-device model, use the CLI or the server - you do not need this library.

## When to depend on `ApfelCore`

Good fit:

- You are writing a Swift app that calls FoundationModels directly and want to speak OpenAI-shaped JSON over the wire.
- You want apfel-plus's context-trimming strategies, tool-call parsing, or MCP protocol types without the CLI binary.
- You want the exact same error classification and retry logic that apfel-plus itself uses.

Not a fit:

- You want to run prompts from the shell -> use the `apfel-plus` CLI.
- You want a local OpenAI-compatible server -> use `apfel-plus --serve`.
- You want FoundationModels itself -> depend on Apple's framework directly. `ApfelCore` is FoundationModels-free by design.

## Install

The first tagged release that contains `ApfelCore` is `1.1.0`. Depend on the package product directly from `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Arthur-Ficial/apfel.git", from: "1.1.0")
],
targets: [
    .executableTarget(
        name: "MyTool",
        dependencies: [
            .product(name: "ApfelCore", package: "apfel-plus")
        ]
    )
]
```

## Quick start

```swift
import ApfelCore

let request = ChatCompletionRequest(
    model: "apple-foundationmodel",
    messages: [OpenAIMessage(role: "user", content: .text("Hello"))]
)
```

See [Examples/](../Examples/) for runnable samples covering OpenAI types, tool calling, MCP protocol, error handling, and context strategies.

## API surface (high level)

| Area | Representative types |
|------|---------------------|
| OpenAI types | `ChatCompletionRequest`, `ChatCompletionResponse`, `OpenAIMessage`, `MessageContent`, `ToolDefinition`, `ResponseFormat` |
| Validation | Request validators for unsupported features (embeddings, logprobs, n>1) |
| Context strategies | `ContextStrategy` with 5 trimming policies |
| Tool calling | `ToolCallHandler`, JSON tool-call detection, schema conversion |
| MCP protocol | Message types + transport-agnostic client primitives |
| Error handling | `ApfelError` with typed error classification |
| Retry logic | `withRetry`, `isRetryableError` |

Full API reference lives in the DocC catalog at [Sources/Core/ApfelCore.docc/](../Sources/Core/ApfelCore.docc/).

## Stability contract

`ApfelCore` follows apfel-plus's semver. Breaking changes require a major version bump and are guarded in CI via `swift package diagnose-api-breaking-changes`. Deprecations land with `@available(*, deprecated, ...)` one release before removal.

Full policy: [STABILITY.md](../STABILITY.md).

## Examples

| Topic | Directory |
|-------|-----------|
| OpenAI request/response shapes | [Examples/OpenAITypes/](../Examples/OpenAITypes/) |
| Tool calling end-to-end | [Examples/ToolCalling/](../Examples/ToolCalling/) |
| MCP protocol primitives | [Examples/MCPProtocol/](../Examples/MCPProtocol/) |
| Error handling + retry | [Examples/ErrorHandling/](../Examples/ErrorHandling/) |
| Context-trimming strategies | [Examples/ContextStrategies/](../Examples/ContextStrategies/) |

## Architecture note

`ApfelCore` contains zero dependencies on FoundationModels or Hummingbird. That is on purpose. The apfel-plus executable composes `ApfelCore` with FoundationModels (for inference) and Hummingbird (for the HTTP server), but the library itself stays pure Swift so it can be unit-tested, cross-compiled, and embedded into apps that do their own FoundationModels calls.
