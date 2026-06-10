# How to use the Apple Foundation Model from Ruby

Call Apple's on-device Foundation Model from Ruby using the `ruby-openai` gem, pointed at a local `apfel-plus --serve`. 100% on-device, zero API cost.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/ruby](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/ruby).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (port `11434`)
- Ruby 2.6+ (ships with macOS)
- `gem install ruby-openai` (or `bundle add ruby-openai`)

## 1. One-shot

```ruby
require "openai"

client = OpenAI::Client.new(
  uri_base: "http://localhost:11434",
  access_token: "not-needed"
)

response = client.chat(
  parameters: {
    model: "apple-foundationmodel",
    messages: [{ role: "user", content: "In one sentence, what is the Swift programming language?" }],
    max_tokens: 80
  }
)

puts response.dig("choices", 0, "message", "content").strip
```

Real output:

```text
Swift is a modern, high-performance, and versatile programming language designed for developing iOS, macOS, watchOS, and tvOS applications.
```

Lab script: [`01_oneshot.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/01_oneshot.rb).

## 2. Streaming

`ruby-openai` streams via a callback `proc`:

```ruby
require "openai"

client = OpenAI::Client.new(uri_base: "http://localhost:11434", access_token: "not-needed")

client.chat(
  parameters: {
    model: "apple-foundationmodel",
    messages: [{ role: "user", content: "List three Apple silicon chips, one per line." }],
    max_tokens: 80,
    stream: proc do |chunk, _bytesize|
      next if chunk.dig("choices").nil? || chunk["choices"].empty?
      piece = chunk.dig("choices", 0, "delta", "content")
      print piece if piece
      $stdout.flush
    end
  }
)
puts
```

Real output:

```text
Apple M1  
Apple M2  
Apple M3
```

Lab script: [`02_stream.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/02_stream.rb).

## 3. JSON mode

```ruby
require "openai"
require "json"

client = OpenAI::Client.new(uri_base: "http://localhost:11434", access_token: "not-needed")

response = client.chat(
  parameters: {
    model: "apple-foundationmodel",
    messages: [{ role: "user", content: "Return JSON with fields 'chip', 'year', 'cores'. Describe the Apple M1 chip. Return ONLY JSON." }],
    response_format: { type: "json_object" },
    max_tokens: 120
  }
)

raw = response.dig("choices", 0, "message", "content").to_s.strip
raw = raw.sub(/\A```(?:json)?\s*/, "").sub(/\s*```\z/, "").strip
puts JSON.pretty_generate(JSON.parse(raw))
```

Real output:

```json
{
  "chip": "Apple M1",
  "year": 2020,
  "cores": {
    "cpu": 8,
    "gpu": 8
  }
}
```

Lab script: [`03_json.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/03_json.rb).

## 4. Error handling

`ruby-openai` surfaces HTTP errors via `Faraday::Error`:

```ruby
require "openai"

client = OpenAI::Client.new(uri_base: "http://localhost:11434", access_token: "not-needed")

begin
  client.embeddings(parameters: { model: "apple-foundationmodel", input: "apfel-plus runs 100% on-device." })
rescue Faraday::Error => e
  status = e.response && e.response[:status]
  puts "Got expected error: HTTP #{status} - #{e.message}"
end
```

Real output:

```text
Got expected error: HTTP 501 - the server responded with status 501
```

Lab script: [`04_errors.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/04_errors.rb).

## 5. Tool calling

```ruby
require "openai"
require "json"

client = OpenAI::Client.new(uri_base: "http://localhost:11434", access_token: "not-needed")

TOOLS = [{
  type: "function",
  function: {
    name: "get_weather",
    description: "Get the current temperature in Celsius for a city.",
    parameters: {
      type: "object",
      properties: { city: { type: "string" } },
      required: ["city"]
    }
  }
}]

def get_weather(args)
  fake = { "Vienna" => 14, "Cupertino" => 19, "Tokyo" => 11 }
  { city: args["city"], temp_c: fake[args["city"]] || 15 }.to_json
end

messages = [{ role: "user", content: "What is the temperature in Vienna right now?" }]
first = client.chat(parameters: { model: "apple-foundationmodel", messages: messages, tools: TOOLS, max_tokens: 256 })
msg = first.dig("choices", 0, "message")
messages << msg

if msg["tool_calls"] && !msg["tool_calls"].empty?
  msg["tool_calls"].each do |call|
    args = JSON.parse(call.dig("function", "arguments"))
    messages << { role: "tool", tool_call_id: call["id"], content: get_weather(args) }
  end
  final = client.chat(parameters: { model: "apple-foundationmodel", messages: messages, max_tokens: 120 })
  puts final.dig("choices", 0, "message", "content").to_s.strip
end
```

Real output:

```text
The current temperature in Vienna is 14 degrees Celsius.
```

Lab script: [`05_tools.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/05_tools.rb).

## 6. Real example - summarize stdin

```ruby
require "openai"

text = $stdin.read.strip
if text.empty?
  warn "usage: cat file.txt | ruby 06_example.rb"
  exit 1
end

client = OpenAI::Client.new(uri_base: "http://localhost:11434", access_token: "not-needed")

response = client.chat(
  parameters: {
    model: "apple-foundationmodel",
    messages: [
      { role: "system", content: "You are a concise summarizer. Reply with one short paragraph." },
      { role: "user", content: "Summarize:\n\n#{text}" }
    ],
    max_tokens: 150
  }
)
puts response.dig("choices", 0, "message", "content").to_s.strip
```

Real output:

```text
The Apple M1 chip, launched in November 2020, marked Apple's first ARM-based system-on-a-chip for Mac computers. It features an 8-core CPU with four performance and four efficiency cores, along with an integrated GPU that can have up to 8 cores. The chip integrates CPU, GPU, memory, and neural engine on a single die, offering significant performance-per-watt improvements over its Intel predecessors.
```

Lab script: [`06_example.rb`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/ruby/06_example.rb).

## Troubleshooting

- **Connection refused** - start `apfel-plus --serve` before running the Ruby script.
- **`e.response[:status]`** - only present when Faraday raises with a full response object. For low-level socket errors it's nil.
- **Rails** - these patterns drop into a Rails controller or background job without changes. Use the same `OpenAI::Client` pointed at localhost.

## Tested with

- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
- Ruby 2.6.10 (system) / ruby-openai 7.4.0
- Date: 2026-04-16

Runnable tests: [tests/test_ruby.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_ruby.py).

## See also

[python.md](python.md), [nodejs.md](nodejs.md), [php.md](php.md), [bash-curl.md](bash-curl.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
