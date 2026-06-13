# LaunchAgent for apfel-plus

`com.tariqwest.apfel-plus.plist` runs `apfel-plus --serve` as a per-user
LaunchAgent. It starts at login, restarts on crash, and serves the
OpenAI-compatible HTTP API on `apfel.localhost:1337`.

## Why a LaunchAgent and not a LaunchDaemon

LaunchDaemons run as root with no user GUI session. The on-device
FoundationModels framework (Apple Intelligence) is only accessible from the
logged-in user's session, so a daemon cannot reach the model and the
server would fail every request with a 503. A LaunchAgent runs inside the
user's session, which is what we need.

In practice on a single-user Mac, the agent starting at login is
equivalent to "starts at computer startup".

## Install

```bash
install -m 0755 .build/out/Products/Release/apfel-plus /usr/local/bin/apfel-plus
cp launchd/com.tariqwest.apfel-plus.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.tariqwest.apfel-plus.plist
```

## Verify

```bash
launchctl print "gui/$(id -u)/com.tariqwest.apfel-plus" | grep -E "^\s*(state|pid) "
curl -s -H "Authorization: Bearer sk-apfel" http://apfel.localhost:1337/health
```

## Manage

```bash
launchctl kickstart -k  "gui/$(id -u)/com.tariqwest.apfel-plus"   # restart
launchctl bootout       "gui/$(id -u)/com.tariqwest.apfel-plus"   # stop + unload
launchctl print         "gui/$(id -u)/com.tariqwest.apfel-plus"   # state, last exit, env
```

## Logs

```
~/Library/Logs/apfel-plus.out.log
~/Library/Logs/apfel-plus.err.log
```

Rotate with `man newsyslog` if needed.

## Notes

- `KeepAlive.SuccessfulExit = false` + `Crashed = true` means launchd
  only respawns on abnormal termination, so a clean `launchctl bootout`
  shuts the server down for good.
- `ThrottleInterval = 10` puts a 10-second floor between respawns to
  prevent crash-loop CPU pegging.
- The bearer token (`sk-apfel`) is in the plist on disk - readable by any
  process running as your user. For a real secret, move it to a file with
  `chmod 600` and reference it via an environment-variable helper script.
