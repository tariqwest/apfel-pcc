# How to use the Apple Foundation Model from Perl

Call Apple's on-device Foundation Model from Perl using `HTTP::Tiny` + `JSON::PP` - both ship with the system Perl on macOS, so no CPAN needed.

Runnable scripts + tests: [Arthur-Ficial/apfel-guides-lab/scripts/perl](https://github.com/Arthur-Ficial/apfel-guides-lab/tree/main/scripts/perl).

## Prerequisites

- macOS 26+ Tahoe, Apple Silicon, Apple Intelligence enabled
- `brew install apfel-plus`
- `apfel-plus --serve` running (port `11434`)
- Perl 5.34+ (ships with macOS at `/usr/bin/perl`)

No `cpanm` required - `HTTP::Tiny` and `JSON::PP` are core modules.

## 1. One-shot

```perl
#!/usr/bin/env perl
use strict;
use warnings;
use HTTP::Tiny;
use JSON::PP;

my $body = encode_json({
    model      => 'apple-foundationmodel',
    messages   => [{ role => 'user', content => 'In one sentence, what is the Swift programming language?' }],
    max_tokens => 80,
});

my $res = HTTP::Tiny->new->request(
    POST => 'http://localhost:11434/v1/chat/completions',
    { headers => { 'Content-Type' => 'application/json' }, content => $body }
);
die "HTTP $res->{status}: $res->{content}\n" unless $res->{success};

my $text = decode_json($res->{content})->{choices}[0]{message}{content} // '';
$text =~ s/^\s+|\s+$//g;
print "$text\n";
```

Real output:

```text
Swift is a modern, safe, and efficient programming language developed by Apple for building user interfaces, server-side applications, and command-line tools.
```

Lab script: [`01_oneshot.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/01_oneshot.pl).

## 2. Streaming

`HTTP::Tiny` supports streaming via `data_callback`:

```perl
#!/usr/bin/env perl
use strict; use warnings;
use HTTP::Tiny; use JSON::PP;

my $body = encode_json({
    model => 'apple-foundationmodel',
    messages => [{ role => 'user', content => 'List three Apple silicon chips, one per line.' }],
    max_tokens => 80,
    stream => JSON::PP::true,
});

my $buf = '';
my $cb = sub {
    my ($chunk) = @_;
    $buf .= $chunk;
    while ($buf =~ s/^(.*?)\r?\n//) {
        my $line = $1;
        next if $line !~ s/^data:\s*//;
        next if $line eq '' || $line eq '[DONE]';
        my $obj = eval { decode_json($line) } or next;
        next unless $obj->{choices} && @{$obj->{choices}};
        my $delta = $obj->{choices}[0]{delta}{content};
        if (defined $delta) { STDOUT->autoflush(1); print $delta; }
    }
};

HTTP::Tiny->new->request(
    POST => 'http://localhost:11434/v1/chat/completions',
    { headers => { 'Content-Type' => 'application/json' }, content => $body, data_callback => $cb }
);
print "\n";
```

Real output:

```text
Apple M1
Apple M2
Apple M3
```

Lab script: [`02_stream.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/02_stream.pl).

## 3. JSON mode

```perl
my $res = HTTP::Tiny->new->request(
    POST => 'http://localhost:11434/v1/chat/completions',
    {
        headers => { 'Content-Type' => 'application/json' },
        content => encode_json({
            model => 'apple-foundationmodel',
            messages => [{ role => 'user', content => "Return JSON with fields chip, year, cores. Describe the Apple M1 chip. Return ONLY JSON." }],
            response_format => { type => 'json_object' },
            max_tokens => 120,
        })
    }
);

my $raw = decode_json($res->{content})->{choices}[0]{message}{content} // '';
$raw =~ s/^\s*```(?:json)?//; $raw =~ s/```\s*$//;
$raw =~ s/^\s+|\s+$//g;

my $parsed = decode_json($raw);
print JSON::PP->new->pretty->canonical->encode($parsed);
```

Real output:

```json
{
   "chip" : "Apple M1",
   "cores" : {
      "cpu" : 8,
      "gpu" : 8
   },
   "year" : 2020
}
```

Lab script: [`03_json.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/03_json.pl).

## 4. Error handling

```perl
my $res = HTTP::Tiny->new->request(
    POST => 'http://localhost:11434/v1/embeddings',
    { headers => { 'Content-Type' => 'application/json' },
      content => encode_json({ model => 'apple-foundationmodel', input => 'apfel-plus runs 100% on-device.' }) }
);

if ($res->{status} >= 400) {
    my $msg = 'see response';
    my $err = eval { decode_json($res->{content}) };
    if ($err && ref $err eq 'HASH' && $err->{error}) {
        $msg = $err->{error}{message} // $msg;
    }
    print "Got expected error: HTTP $res->{status} - $msg\n";
}
```

Real output:

```text
Got expected error: HTTP 501 - Embeddings not supported by Apple's on-device model.
```

Lab script: [`04_errors.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/04_errors.pl).

## 5. Tool calling

Full round-trip; see [`05_tools.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/05_tools.pl) for the complete script. Key snippet:

```perl
binmode STDOUT, ':encoding(UTF-8)';  # avoid issues with °C, EUR etc.

my $TOOLS = [{
    type => 'function',
    function => {
        name => 'get_weather',
        description => 'Get the current temperature in Celsius for a city.',
        parameters => { type => 'object',
            properties => { city => { type => 'string' } }, required => ['city'] },
    },
}];

# first call with tools, check $msg->{tool_calls}, answer, second call for final reply
```

Real output:

```text
The current temperature in Vienna is 14°C.
```

## 6. Real example - summarize stdin

```perl
my $text = do { local $/; <STDIN> };
$text //= ''; $text =~ s/^\s+|\s+$//g;
die "usage: cat file.txt | perl 06_example.pl\n" unless length $text;

my $body = encode_json({
    model => 'apple-foundationmodel',
    messages => [
        { role => 'system', content => 'You are a concise summarizer. Reply with one short paragraph.' },
        { role => 'user', content => "Summarize:\n\n$text" },
    ],
    max_tokens => 150,
});

my $res = HTTP::Tiny->new->request(
    POST => 'http://localhost:11434/v1/chat/completions',
    { headers => { 'Content-Type' => 'application/json' }, content => $body }
);
my $content = decode_json($res->{content})->{choices}[0]{message}{content} // '';
$content =~ s/^\s+|\s+$//g;
print "$content\n";
```

Real output:

```text
The Apple M1 chip, released in November 2020, was Apple's first ARM-based system-on-a-chip for Mac computers. It uses an 8-core CPU with four performance and four efficiency cores, plus an integrated GPU with up to 8 cores. The chip unified CPU, GPU, memory, and neural engine on a single die, delivering significant performance-per-watt improvements over the Intel chips it replaced.
```

Lab script: [`06_example.pl`](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/scripts/perl/06_example.pl).

## Troubleshooting

- **UTF-8 garbage on terminal** - `binmode STDOUT, ':encoding(UTF-8)';` at the top of the script. macOS's system Perl doesn't set this by default.
- **Want LWP::UserAgent instead** - both work; HTTP::Tiny keeps the dependency footprint at zero on macOS.
- **Streaming buffered** - make sure you do `STDOUT->autoflush(1)` inside the callback.

## Tested with

- apfel-plus v1.0.3 / macOS 26.3.1 Apple Silicon
- Perl 5.34.1 (system) / HTTP::Tiny 0.076 / JSON::PP 4.06
- Date: 2026-04-16

Runnable tests: [tests/test_perl.py](https://github.com/Arthur-Ficial/apfel-guides-lab/blob/main/tests/test_perl.py).

## See also

[python.md](python.md), [ruby.md](ruby.md), [bash-curl.md](bash-curl.md), [awk.md](awk.md), [apfel-guides-lab](https://github.com/Arthur-Ficial/apfel-guides-lab)
