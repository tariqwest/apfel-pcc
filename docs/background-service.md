# Background Service

Run apfel-plus's OpenAI-compatible server in the background using Homebrew services. Same pattern as Ollama, PostgreSQL, nginx.

## Quick Start

```bash
brew services start apfel-plus
```

The server starts at `http://127.0.0.1:11434` and auto-restarts on crash or login.

## Commands

```bash
brew services start apfel-plus          # Start (auto-starts at login)
brew services stop apfel-plus           # Stop
brew services restart apfel-plus        # Restart
brew services info apfel           # Status
brew services list                 # All services
```

## Logs

```bash
tail -f /opt/homebrew/var/log/apfel-plus.log
```

## Configuration via Environment

apfel-plus reads configuration from environment variables. Set them before starting the service:

```bash
# Custom port
APFEL_PORT=8080 brew services start apfel-plus

# Token authentication
APFEL_TOKEN="my-secret" brew services start apfel-plus
APFEL_TOKEN=$(uuidgen) brew services start apfel-plus

# Attach MCP tool servers (colon-separated paths)
APFEL_MCP="/path/to/server.py" brew services start apfel-plus
APFEL_MCP="/path/a.py:/path/b.py" brew services start apfel-plus

# MCP timeout for slow/remote servers (default: 5s, max: 300s)
APFEL_MCP_TIMEOUT=30 APFEL_MCP="/path/to/remote-server.py" brew services start apfel-plus

# System prompt
APFEL_SYSTEM_PROMPT="Be concise" brew services start apfel-plus

# Custom host (expose to network - see security note below)
APFEL_HOST=0.0.0.0 APFEL_TOKEN=$(uuidgen) brew services start apfel-plus
```

All `APFEL_*` variables: see `apfel-plus --help` under ENVIRONMENT.

## Security

The background service uses the same security model as `apfel-plus --serve`:

- **Default: localhost only.** Binds to `127.0.0.1` unless `APFEL_HOST` overrides.
- **Token auth.** Set `APFEL_TOKEN` for Bearer authentication.
- **When exposing to network** (`APFEL_HOST=0.0.0.0`), always set a token:
  ```bash
  APFEL_HOST=0.0.0.0 APFEL_TOKEN=$(uuidgen) brew services start apfel-plus
  ```

See [Server Security](server-security.md) for full details.

## Manual Plist (Advanced)

For configurations that Homebrew's service doesn't cover (custom flags, complex MCP setups), create a plist manually:

```bash
cat > ~/Library/LaunchAgents/com.arthurficial.apfel-plus.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.arthurficial.apfel-plus</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/opt/apfel-plus/bin/apfel-plus</string>
        <string>--serve</string>
        <string>--port</string>
        <string>11434</string>
        <string>--mcp</string>
        <string>/absolute/path/to/server.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/apfel-plus.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/apfel-plus.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>/Users/YOUR_USERNAME</string>
        <key>APFEL_TOKEN</key>
        <string>YOUR_TOKEN</string>
    </dict>
</dict>
</plist>
EOF

# Load
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.arthurficial.apfel-plus.plist

# Unload
launchctl bootout gui/$(id -u)/com.arthurficial.apfel-plus

# Check status
launchctl print gui/$(id -u)/com.arthurficial.apfel-plus
```

Use `/opt/homebrew/opt/apfel-plus/bin/apfel-plus` (not the Cellar path) so it survives `brew upgrade`.
