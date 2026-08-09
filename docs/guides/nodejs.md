# How to use the Apple Foundation Model from Node.js

Call Apple's on-device Foundation Model from Node.js using the official `openai` npm package, pointed at a local `apfel-plus --serve`. 100% on-device, zero API cost.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/nodejs](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/nodejs).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (port `11434`)
- Node.js 20+
- `npm install openai`
- `"type": "module"` in `package.json` (or use `.mjs` files)

## 1. One-shot chat completion

```js
import OpenAI from "openai";

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

const response = await client.chat.completions.create({
  model: "apple-foundationmodel",
  messages: [{ role: "user", content: "In one sentence, what is the Swift programming language?" }],
  max_tokens: 80,
});

console.log((response.choices[0].message.content || "").trim());
```

Real output:

```text
Swift is a modern, high-performance, and easy-to-learn programming language developed by Apple for building applications on iOS, macOS, watchOS, and tvOS.
```

Lab script: [`01_oneshot.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/01_oneshot.mjs).

## 2. Streaming

```js
import OpenAI from "openai";

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

const stream = await client.chat.completions.create({
  model: "apple-foundationmodel",
  messages: [{ role: "user", content: "List three Apple silicon chips, one per line." }],
  max_tokens: 80,
  stream: true,
});

for await (const chunk of stream) {
  if (!chunk.choices || chunk.choices.length === 0) continue;
  const delta = chunk.choices[0].delta?.content ?? "";
  process.stdout.write(delta);
}
process.stdout.write("\n");
```

Real output:

```text
Apple M1
Apple M2
Apple M2 Pro
```

Lab script: [`02_stream.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/02_stream.mjs).

## 3. JSON mode

```js
import OpenAI from "openai";

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

const response = await client.chat.completions.create({
  model: "apple-foundationmodel",
  messages: [{
    role: "user",
    content: "Return JSON with fields 'chip', 'year', 'cores'. Describe the Apple M1 chip. Return ONLY JSON.",
  }],
  response_format: { type: "json_object" },
  max_tokens: 120,
});

let raw = (response.choices[0].message.content || "").trim();
raw = raw.replace(/^```(?:json)?\s*|\s*```$/gm, "").trim();
console.log(JSON.stringify(JSON.parse(raw), null, 2));
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

Lab script: [`03_json.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/03_json.mjs).

## 4. Error handling

```js
import OpenAI from "openai";

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

try {
  await client.embeddings.create({
    model: "apple-foundationmodel",
    input: "apfel-plus runs 100% on-device.",
  });
} catch (err) {
  if (err instanceof OpenAI.APIError) {
    console.log(`Got expected error: HTTP ${err.status} - ${err.message}`);
  } else {
    throw err;
  }
}
```

Real output:

```text
Got expected error: HTTP 501 - 501 Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/04_errors.mjs).

## 5. Tool calling

```js
import OpenAI from "openai";

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

const tools = [{
  type: "function",
  function: {
    name: "get_weather",
    description: "Get the current temperature in Celsius for a city.",
    parameters: {
      type: "object",
      properties: { city: { type: "string", description: "City name" } },
      required: ["city"],
    },
  },
}];

function getWeather({ city }) {
  const fake = { Vienna: 14, Cupertino: 19, Tokyo: 11 };
  return JSON.stringify({ city, temp_c: fake[city] ?? 15 });
}

const messages = [{ role: "user", content: "What is the temperature in Vienna right now?" }];

const first = await client.chat.completions.create({
  model: "apple-foundationmodel", messages, tools, max_tokens: 256,
});
const msg = first.choices[0].message;
messages.push(msg);

if (msg.tool_calls?.length) {
  for (const call of msg.tool_calls) {
    const args = JSON.parse(call.function.arguments);
    messages.push({ role: "tool", tool_call_id: call.id, content: getWeather(args) });
  }
  const final = await client.chat.completions.create({
    model: "apple-foundationmodel", messages, max_tokens: 120,
  });
  console.log((final.choices[0].message.content || "").trim());
}
```

Real output:

```text
The current temperature in Vienna is 14 degrees Celsius.
```

Lab script: [`05_tools.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/05_tools.mjs).

## 6. Real example - summarize stdin

```js
import OpenAI from "openai";

const text = await new Promise((resolve) => {
  let buf = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (c) => (buf += c));
  process.stdin.on("end", () => resolve(buf.trim()));
});

if (!text) {
  console.error("usage: cat file.txt | node 06_example.mjs");
  process.exit(1);
}

const client = new OpenAI({ baseURL: "http://localhost:11434/v1", apiKey: "not-needed" });

const response = await client.chat.completions.create({
  model: "apple-foundationmodel",
  messages: [
    { role: "system", content: "You are a concise summarizer. Reply with one short paragraph." },
    { role: "user", content: `Summarize:\n\n${text}` },
  ],
  max_tokens: 150,
});
console.log((response.choices[0].message.content || "").trim());
```

Real output (M1 paragraph):

```text
The Apple M1 chip, released in November 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It uses an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores. The chip unified CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.mjs`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/nodejs/06_example.mjs).

## Troubleshooting

- **`ECONNREFUSED`** - start `apfel-plus --serve` before running your Node script.
- **Missing `choices[0]` during streaming** - handle the final usage chunk with the `if (!chunk.choices || chunk.choices.length === 0) continue;` guard above.
- **TypeScript** - same code works; `npm install -D @types/node` for Node types.

## Tested with

<<<<<<< HEAD
- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
=======
- apfel v1.0.3 / macOS 26.3.1 Apple Silicon (original capture; the CLI and HTTP surfaces used here are release-gated by apfel's test suite on every version)
>>>>>>> upstream/main
- Node.js v25.8.1 / openai 4.x
- Date: 2026-04-16

Runnable tests: [tests/test_nodejs.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_nodejs.py).

## See also

[python.md](python.md), [ruby.md](ruby.md), [php.md](php.md), [bash-curl.md](bash-curl.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
