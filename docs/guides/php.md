# How to use the Apple Foundation Model from PHP

Call Apple's on-device Foundation Model from PHP using `openai-php/client`, pointed at a local `apfel-plus --serve`. 100% on-device, zero API cost.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/php](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/php).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (port `11434`)
- PHP 8.1+ and Composer (`brew install php composer`)
- `composer require openai-php/client guzzlehttp/guzzle`

> `openai-php/client` needs a PSR-18 HTTP client; Guzzle is the usual pick.

## 1. One-shot

```php
<?php
require __DIR__ . "/vendor/autoload.php";

$client = OpenAI::factory()
    ->withBaseUri("http://localhost:11434/v1")
    ->withApiKey("not-needed")
    ->make();

$response = $client->chat()->create([
    "model" => "apple-foundationmodel",
    "messages" => [
        ["role" => "user", "content" => "In one sentence, what is the Swift programming language?"],
    ],
    "max_tokens" => 80,
]);

echo trim($response->choices[0]->message->content ?? "") . "\n";
```

Real output:

```text
Swift is a modern, open-source programming language developed by Apple for developing software on platforms like iOS, macOS, watchOS, and tvOS, known for its safety, performance, and simplicity.
```

Lab script: [`01_oneshot.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/01_oneshot.php).

## 2. Streaming

Use `createStreamed` and `foreach`:

```php
<?php
require __DIR__ . "/vendor/autoload.php";

$client = OpenAI::factory()->withBaseUri("http://localhost:11434/v1")->withApiKey("not-needed")->make();

$stream = $client->chat()->createStreamed([
    "model" => "apple-foundationmodel",
    "messages" => [["role" => "user", "content" => "List three Apple silicon chips, one per line."]],
    "max_tokens" => 80,
]);

foreach ($stream as $response) {
    if (empty($response->choices)) continue;
    echo $response->choices[0]->delta->content ?? "";
    flush();
}
echo "\n";
```

Real output:

```text
Apple M1
Apple M2
Apple M2 Pro
```

Lab script: [`02_stream.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/02_stream.php).

## 3. JSON mode

```php
<?php
require __DIR__ . "/vendor/autoload.php";

$client = OpenAI::factory()->withBaseUri("http://localhost:11434/v1")->withApiKey("not-needed")->make();

$response = $client->chat()->create([
    "model" => "apple-foundationmodel",
    "messages" => [["role" => "user", "content" => "Return JSON with fields 'chip', 'year', 'cores'. Describe the Apple M1 chip. Return ONLY JSON."]],
    "response_format" => ["type" => "json_object"],
    "max_tokens" => 120,
]);

$raw = trim($response->choices[0]->message->content ?? "");
$raw = preg_replace('/\A```(?:json)?\s*|\s*```\z/m', "", $raw);
$data = json_decode(trim($raw), true, flags: JSON_THROW_ON_ERROR);
echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
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

Lab script: [`03_json.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/03_json.php).

## 4. Error handling

```php
<?php
require __DIR__ . "/vendor/autoload.php";
use OpenAI\Exceptions\ErrorException;

$client = OpenAI::factory()->withBaseUri("http://localhost:11434/v1")->withApiKey("not-needed")->make();

try {
    $client->embeddings()->create([
        "model" => "apple-foundationmodel",
        "input" => "apfel-plus runs 100% on-device.",
    ]);
} catch (ErrorException $e) {
    echo "Got expected error (HTTP 501): {$e->getMessage()}\n";
}
```

Real output:

```text
Got expected error (HTTP 501): Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/04_errors.php).

## 5. Tool calling

```php
<?php
require __DIR__ . "/vendor/autoload.php";

$client = OpenAI::factory()->withBaseUri("http://localhost:11434/v1")->withApiKey("not-needed")->make();

$tools = [[
    "type" => "function",
    "function" => [
        "name" => "get_weather",
        "description" => "Get the current temperature in Celsius for a city.",
        "parameters" => [
            "type" => "object",
            "properties" => ["city" => ["type" => "string"]],
            "required" => ["city"],
        ],
    ],
]];

function get_weather(array $args): string {
    $fake = ["Vienna" => 14, "Cupertino" => 19, "Tokyo" => 11];
    $city = $args["city"] ?? "";
    return json_encode(["city" => $city, "temp_c" => $fake[$city] ?? 15]);
}

$messages = [["role" => "user", "content" => "What is the temperature in Vienna right now?"]];

$first = $client->chat()->create([
    "model" => "apple-foundationmodel", "messages" => $messages, "tools" => $tools, "max_tokens" => 256,
]);
$msg = $first->choices[0]->message;
$messages[] = $msg->toArray();

if (!empty($msg->toolCalls)) {
    foreach ($msg->toolCalls as $call) {
        $args = json_decode($call->function->arguments, true) ?? [];
        $messages[] = ["role" => "tool", "tool_call_id" => $call->id, "content" => get_weather($args)];
    }
    $final = $client->chat()->create([
        "model" => "apple-foundationmodel", "messages" => $messages, "max_tokens" => 120,
    ]);
    echo trim($final->choices[0]->message->content ?? "") . "\n";
}
```

Real output:

```text
The current temperature in Vienna is 15°C.
```

Lab script: [`05_tools.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/05_tools.php).

## 6. Real example - summarize stdin

```php
<?php
require __DIR__ . "/vendor/autoload.php";

$text = trim(stream_get_contents(STDIN));
if ($text === "") {
    fwrite(STDERR, "usage: cat file.txt | php 06_example.php\n");
    exit(1);
}

$client = OpenAI::factory()->withBaseUri("http://localhost:11434/v1")->withApiKey("not-needed")->make();

$response = $client->chat()->create([
    "model" => "apple-foundationmodel",
    "messages" => [
        ["role" => "system", "content" => "You are a concise summarizer. Reply with one short paragraph."],
        ["role" => "user", "content" => "Summarize:\n\n$text"],
    ],
    "max_tokens" => 150,
]);
echo trim($response->choices[0]->message->content ?? "") . "\n";
```

Real output:

```text
Apple's M1 chip, released in November 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It uses an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores. The chip unified CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.php`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/php/06_example.php).

## Troubleshooting

- **`No PSR-18 clients found`** - `composer require guzzlehttp/guzzle`.
- **TLS / SSL errors** - make sure your `baseUri` starts with `http://`, not `https://`.
- **Laravel / Symfony** - works inside any container; register `OpenAI::factory()->make()` as a singleton pointed at `APFEL_BASE_URL`.

## Tested with

<<<<<<< HEAD
- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
=======
- apfel v1.0.3 / macOS 26.3.1 Apple Silicon (original capture; the CLI and HTTP surfaces used here are release-gated by apfel's test suite on every version)
>>>>>>> upstream/main
- PHP 8.5.5 / openai-php/client 0.10.3 / Guzzle
- Date: 2026-04-16

Runnable tests: [tests/test_php.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_php.py).

## See also

[python.md](python.md), [nodejs.md](nodejs.md), [ruby.md](ruby.md), [bash-curl.md](bash-curl.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
