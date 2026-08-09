# How to use the Apple Foundation Model from Swift scripts

Call Apple's on-device Foundation Model from a Swift script using `URLSession`. This is the "shell script written in Swift" pattern - fast, native, and pointed at a local `apfel-plus --serve`.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/swift-scripting](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/swift-scripting).

> For **in-app** use, you can skip apfel-plus entirely and call `FoundationModels` directly via Apple's own Swift SDK. This guide is for **scripts** - anything you'd run with `swift path/to/file.swift` from the command line.

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (port `11434`)
- Xcode Command Line Tools (`xcode-select --install`) - Swift 6 ships with the OS

Swift scripts use `#!/usr/bin/env swift` or just `swift file.swift`.

## 1. One-shot

```swift
#!/usr/bin/env swift
import Foundation

struct ChatRequest: Encodable {
  struct Message: Encodable { let role, content: String }
  let model: String
  let messages: [Message]
  let max_tokens: Int
}

struct ChatResponse: Decodable {
  struct Choice: Decodable { struct Msg: Decodable { let content: String? }; let message: Msg }
  let choices: [Choice]
}

var req = URLRequest(url: URL(string: "http://localhost:11434/v1/chat/completions")!)
req.httpMethod = "POST"
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.httpBody = try JSONEncoder().encode(ChatRequest(
  model: "apple-foundationmodel",
  messages: [.init(role: "user", content: "In one sentence, what is the Swift programming language?")],
  max_tokens: 80
))

let sem = DispatchSemaphore(value: 0)
var finalText = ""
URLSession.shared.dataTask(with: req) { data, _, _ in
  defer { sem.signal() }
  guard let data = data,
        let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
        let text = decoded.choices.first?.message.content
  else { return }
  finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
}.resume()
sem.wait()
print(finalText)
```

Real output:

```text
Swift is a modern, open-source programming language known for its safety features, ease of use, and performance, primarily used for developing iOS, macOS, watchOS, and tvOS applications.
```

Lab script: [`01_oneshot.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/01_oneshot.swift).

## 2. Streaming

Use `URLSession.shared.bytes(for:)` and parse SSE lines as they arrive:

```swift
#!/usr/bin/env swift
import Foundation

let body: [String: Any] = [
  "model": "apple-foundationmodel",
  "messages": [["role": "user", "content": "List three Apple silicon chips, one per line."]],
  "max_tokens": 80,
  "stream": true,
]
var req = URLRequest(url: URL(string: "http://localhost:11434/v1/chat/completions")!)
req.httpMethod = "POST"
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
req.httpBody = try JSONSerialization.data(withJSONObject: body)

let sem = DispatchSemaphore(value: 0)
Task {
  defer { sem.signal() }
  let (bytes, _) = try await URLSession.shared.bytes(for: req)
  for try await line in bytes.lines {
    var payload = line
    if payload.hasPrefix("data: ") { payload.removeFirst("data: ".count) }
    guard !payload.isEmpty, payload != "[DONE]" else { continue }
    guard let data = payload.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choices = obj["choices"] as? [[String: Any]],
          let delta = choices.first?["delta"] as? [String: Any],
          let content = delta["content"] as? String
    else { continue }
    FileHandle.standardOutput.write(content.data(using: .utf8) ?? Data())
  }
  print()
}
sem.wait()
```

Real output:

```text
Sure! Here are three Apple silicon chips:

- M1
- M2
- M3
```

Lab script: [`02_stream.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/02_stream.swift).

## 3. JSON mode

```swift
let body: [String: Any] = [
  "model": "apple-foundationmodel",
  "messages": [["role": "user", "content": "Return JSON with fields chip, year, cores. Describe the Apple M1 chip. Return ONLY JSON."]],
  "response_format": ["type": "json_object"],
  "max_tokens": 120,
]
// ... (same URLSession dance as above) ...
var stripped = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
stripped = stripped.replacingOccurrences(of: "```json", with: "")
                   .replacingOccurrences(of: "```", with: "")
                   .trimmingCharacters(in: .whitespacesAndNewlines)

let parsed = try JSONSerialization.jsonObject(with: Data(stripped.utf8))
let pretty = try JSONSerialization.data(withJSONObject: parsed, options: [.prettyPrinted, .sortedKeys])
print(String(data: pretty, encoding: .utf8) ?? "")
```

Real output:

```json
{
  "chip" : "Apple M1",
  "cores" : {
    "CPU" : {
      "count" : 8,
      "type" : "High-performance"
    },
    "GPU" : {
      "count" : 8,
      "type" : "High-efficiency"
    }
  },
  "year" : 2020
}
```

Full script: [`03_json.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/03_json.swift).

## 4. Error handling

Check the `HTTPURLResponse.statusCode`:

```swift
URLSession.shared.dataTask(with: req) { data, response, _ in
  guard let http = response as? HTTPURLResponse else { return }
  if http.statusCode >= 400 {
    var msg = "see response"
    if let data = data,
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let err = obj["error"] as? [String: Any],
       let m = err["message"] as? String { msg = m }
    print("Got expected error: HTTP \(http.statusCode) - \(msg)")
  }
}.resume()
```

Real output:

```text
Got expected error: HTTP 501 - Embeddings not supported by Apple's on-device model.
```

Full script: [`04_errors.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/04_errors.swift).

## 5. Tool calling

Standard OpenAI tool-calling round-trip via two `URLSession` POSTs. See the full script: [`05_tools.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/05_tools.swift).

Real output:

```text
The current temperature in Vienna is 14 degrees Celsius.
```

## 6. Real example - summarize stdin

```swift
let stdin = FileHandle.standardInput.readDataToEndOfFile()
guard let text = String(data: stdin, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
      !text.isEmpty
else { exit(1) }

let body: [String: Any] = [
  "model": "apple-foundationmodel",
  "messages": [
    ["role": "system", "content": "You are a concise summarizer. Reply with one short paragraph."],
    ["role": "user", "content": "Summarize:\n\n\(text)"],
  ],
  "max_tokens": 150,
]
// URLSession POST as in example 1, print trimmed content
```

Real output:

```text
Apple released their first ARM-based system-on-a-chip for Mac computers in November 2020. It has an 8-core CPU with four performance cores and four efficiency cores, plus an integrated GPU with up to 8 cores. It unified CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Full script: [`06_example.swift`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/swift-scripting/06_example.swift).

## Troubleshooting

- **`swift` is slow to start** - `swift file.swift` compiles on every run. For hot-loop scripts, compile once: `swiftc -O file.swift -o bin && ./bin`.
- **Concurrency warnings on Swift 6** - the scripts use `DispatchSemaphore` to bridge async URLSession into a sync script. Inside an app, switch to `async/await` everywhere.
- **Want tighter types** - define `Codable` structs for every response shape. The one-shot example above shows the pattern.

## Tested with

<<<<<<< HEAD
- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
=======
- apfel v1.0.3 / macOS 26.3.1 Apple Silicon (original capture; the CLI and HTTP surfaces used here are release-gated by apfel's test suite on every version)
>>>>>>> upstream/main
- Swift 6.3 (system)
- Date: 2026-04-16

Runnable tests: [tests/test_swift_scripting.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_swift_scripting.py).

## See also

[applescript.md](applescript.md), [python.md](python.md), [nodejs.md](nodejs.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
