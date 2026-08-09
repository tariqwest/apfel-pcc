# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | Yes       |
| < 1.0   | No        |

## Reporting a Vulnerability

If you believe you have found a security vulnerability in apfel, please report it responsibly. Do NOT file a public GitHub issue.

**Preferred:** Use GitHub's private vulnerability reporting:
https://github.com/Arthur-Ficial/apfel/security/advisories/new

**Alternative:** Email fe at f19n dot com with:
- Description of the vulnerability
- Steps to reproduce
- Expected vs actual behavior
- Your apfel version (`apfel --version`)

## Response Timeline

- Acknowledgment: within 3 business days
- Assessment: within 10 business days
- Fix (if confirmed): target 30 days, may vary by severity

## Scope

apfel runs 100% on-device. There are no cloud calls for inference. The security surface is:

- **HTTP server** (`apfel --serve`) - OpenAI-compatible API on localhost
- **MCP tool execution** (`--mcp`) - subprocess spawning and IPC
- **CLI argument parsing** - flag handling and file reading (`-f`)
- **Origin validation** - CORS and CSRF protection for the server

Issues in Apple's FoundationModels framework itself should be reported to Apple: https://developer.apple.com/bug-reporting/

## Security Design

- Server binds to localhost only by default
- Origin validation rejects cross-origin requests unless `--no-origin-check` (or `--footgun`) is set
- Bearer token authentication available via `--token` or `APFEL_TOKEN`
- Origin- and guardrail-loosening flags (`--no-origin-check`, `--footgun`, `--permissive`) require explicit opt-in
- No secrets stored on disk; tokens are passed via environment variables or flags
