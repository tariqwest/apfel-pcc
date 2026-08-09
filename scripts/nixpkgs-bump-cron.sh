#!/usr/bin/env bash
# nixpkgs-bump-cron.sh - launchd wrapper around publish-nixpkgs-bump.sh that
# turns a silently-failing bump into a single, actionable email to Franz.
#
# WHY THIS EXISTS: the bump script is deliberately NON-FATAL (it must never
# block a release), and the twice-daily launchd agent discarded its exit code.
# So when a GitHub 2FA-compliance break stopped PR creation, the bump failed
# every run for DAYS with nobody told. This wrapper reads the bump's classified
# outcome (its final `NIXPKGS_BUMP_STATUS=<TOKEN> version=<X.Y.Z>` line) and:
#   - benign outcomes (in sync, PR opened/advanced/waiting, tooling skip) -> stay
#     silent and CLEAR the dedup state, so a future regression re-alerts;
#   - actionable failures (2FA, build, push, PR-create, auth, fork, unknown) ->
#     email Franz, but only ONCE per distinct (status, version) so a persistent
#     failure does not mail twice a day forever.
# The wrapper itself always exits 0: the email, not the exit code, is the signal.
#
# Env knobs (used by tests): NIXPKGS_BUMP_SCRIPT, NIXPKGS_BUMP_ALERT_TO,
# XDG_STATE_HOME.
set -uo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUMP="${NIXPKGS_BUMP_SCRIPT:-$REPO_ROOT/scripts/publish-nixpkgs-bump.sh}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/apfel"
STATE_FILE="$STATE_DIR/nixpkgs-bump-alert.state"
LOG="$HOME/Library/Logs/apfel-nixpkgs-bump.log"
ALERT_TO="${NIXPKGS_BUMP_ALERT_TO:-franz.enzenhofer@fullstackoptimization.com}"
mkdir -p "$STATE_DIR"

# Run the bump, capturing combined output. No `set -e`: a non-zero bump must NOT
# abort the wrapper - inspecting and alerting on it is the whole job.
out=$("$BUMP" "$@" 2>&1)
printf '%s\n' "$out"   # still flows to the launchd StandardOutPath log

status_line=$(printf '%s\n' "$out" | grep -E '^NIXPKGS_BUMP_STATUS=' | tail -1)
status=$(sed -E 's/^NIXPKGS_BUMP_STATUS=([A-Z_0-9]+).*/\1/' <<<"$status_line")
version=$(sed -E 's/.* version=([^ ]+).*/\1/' <<<"$status_line")
[[ -z "$status" ]] && status="UNKNOWN_FAIL"   # bump died before finish()
[[ -z "$version" ]] && version="unknown"

is_actionable() {
  case "$1" in
    AUTH_2FA|AUTH_GENERIC|BUILD_FAIL|PUSH_FAIL|PR_CREATE_FAIL|FORK_FAIL|INVALID_VERSION|UNKNOWN_FAIL)
      return 0 ;;
    *) return 1 ;;
  esac
}

if is_actionable "$status"; then
  key="$status $version"
  prev=$(cat "$STATE_FILE" 2>/dev/null || true)
  if [[ "$key" != "$prev" ]]; then
    case "$status" in
      AUTH_2FA)  hint="FIX: NixOS requires authenticator/passkey 2FA. Remove the SMS factor from the Arthur-Ficial GitHub account (Settings -> Password and authentication -> SMS/Text message -> Disable). TOTP stays the anchor; recovery codes are in 'pass show github/recovery-codes'. Then re-run: $BUMP --version $version" ;;
      BUILD_FAIL) hint="FIX: nix-build failed - see /tmp/apfel-nixpkgs-build.log" ;;
      AUTH_GENERIC) hint="FIX: gh CLI is not authenticated - run 'gh auth login' then re-run the bump." ;;
      PUSH_FAIL) hint="FIX: git push to the fork failed - check network and the Arthur-Ficial/nixpkgs fork." ;;
      *) hint="" ;;
    esac
    {
      echo "The twice-daily nixpkgs apfel-llm bump is failing and needs attention."
      echo
      echo "Status:  $status"
      echo "Version: $version"
      [[ -n "$hint" ]] && { echo; echo "$hint"; }
      echo
      echo "Last lines of this run:"
      printf '%s\n' "$out" | tail -25
      echo
      echo "Full log: $LOG"
      echo
      echo "Cheers, Arthur Ficial"
    } | hm-send "$ALERT_TO" "apfel nixpkgs bump FAILED: $status (v$version)" \
      && echo "[cron] alerted Franz: $key" \
      || echo "[cron] WARN: hm-send failed; could not alert ($key)"
    printf '%s' "$key" > "$STATE_FILE"
  else
    echo "[cron] still failing ($key) - already alerted, staying quiet"
  fi
else
  # Benign / success: clear state so the NEXT genuine failure re-alerts.
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    echo "[cron] recovered ($status) - cleared alert state"
  fi
  echo "[cron] ok: $status v$version"
fi

exit 0
