#!/usr/bin/env bash
# nixpkgs-automerge.sh - keep nixpkgs apfel-llm current with ZERO manual steps.
#
# The canonical zero-touch nixpkgs flow (per RFC 172 / ci/README.md):
#   1. r-ryantm opens a bump PR for apfel-llm after each upstream release
#   2. the package maintainer comments "@NixOS/nixpkgs-merge-bot merge"
#   3. the merge bot verifies constraints and merges
#
# The merge bot only acts on PRs opened by r-ryantm (or committers), so our
# own bump PRs can never use it - worse, an open bump PR of ours BLOCKS
# r-ryantm from opening its own. This script reconciles everything:
#
#   - no-op until arthurficial is listed as apfel-llm maintainer in master
#   - accepts a pending NixOS org invite (needed for merge-bot eligibility)
#   - closes our own legacy bump PRs so r-ryantm is unblocked
#   - finds the open r-ryantm apfel-llm PR, verifies its version and SRI hash
#     against the tarball we actually published on GitHub Releases, then
#     posts the merge-bot comment (once per PR)
#
# Safe to run any time (idempotent); wired into `make release` via
# publish-nixpkgs-bump.sh and into a daily launchd agent (see docs/nixpkgs.md).
#
# Usage:
#   ./scripts/nixpkgs-automerge.sh                 # target = latest GitHub release
#   ./scripts/nixpkgs-automerge.sh --version 1.5.3 # explicit target
#   ./scripts/nixpkgs-automerge.sh --dry-run       # report, change nothing
set -euo pipefail

UPSTREAM="NixOS/nixpkgs"
APFEL_REPO="Arthur-Ficial/apfel"
PACKAGE_PATH="pkgs/by-name/ap/apfel-llm/package.nix"
MAINTAINER_LOGIN="Arthur-Ficial"
MERGE_COMMAND="@NixOS/nixpkgs-merge-bot merge"

version=""
dry_run=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

info() { echo "===> $*"; }
warn() { echo "WARN: $*" >&2; }

for tool in gh curl python3; do
  command -v "$tool" >/dev/null 2>&1 || { warn "$tool not found - skipping"; exit 0; }
done
gh api user >/dev/null 2>&1 || { warn "gh not authenticated - skipping"; exit 0; }

# --- Target version: latest published GitHub release ---
if [[ -z "$version" ]]; then
  version=$(gh api "repos/$APFEL_REPO/releases/latest" --jq .tag_name | sed 's/^v//')
fi
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "could not determine a valid target version (got '$version') - skipping"
  exit 0
fi
info "Target version: $version"

# --- Gate: maintainership must be live in nixpkgs master ---
master_pkg=$(curl -fsSL "https://raw.githubusercontent.com/$UPSTREAM/master/$PACKAGE_PATH" 2>/dev/null || true)
if [[ -z "$master_pkg" ]]; then
  warn "could not fetch $PACKAGE_PATH from nixpkgs master - skipping"
  exit 0
fi
if ! grep -q "arthurficial" <<<"$master_pkg"; then
  info "arthurficial not yet a maintainer of apfel-llm in nixpkgs master - nothing to do"
  info "(waiting on https://github.com/NixOS/nixpkgs/pull/524394; legacy bump-PR flow still applies)"
  exit 0
fi
info "Maintainership active in nixpkgs master."

# --- One-time: accept a pending NixOS org invite (merge bot requires
#     membership in @NixOS/nixpkgs-maintainers; the invite is sent
#     automatically after the maintainer-list change lands). 404 = no invite.
if ! $dry_run; then
  if gh api user/memberships/orgs/NixOS -X PATCH -f state=active >/dev/null 2>&1; then
    info "Accepted pending NixOS org invitation."
  fi
fi

# --- Already current? ---
master_version=$(grep -E '^\s*version = "' <<<"$master_pkg" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
if [[ "$master_version" == "$version" ]]; then
  info "nixpkgs master already at $version - nothing to do"
  exit 0
fi
info "nixpkgs master at $master_version, target $version."

# --- Close our own bump PRs: they cannot be merge-bot merged and they block
#     r-ryantm from opening its own bump PR.
own_bumps=$(gh pr list --repo "$UPSTREAM" --state open --search "apfel-llm in:title" \
  --json number,headRefName,headRepositoryOwner,author \
  --jq "[.[] | select(.headRepositoryOwner.login==\"$MAINTAINER_LOGIN\")
             | select(.headRefName | test(\"^apfel-llm-(bump|[0-9])\"))
             | .number] | .[]" 2>/dev/null || true)
for pr in $own_bumps; do
  if $dry_run; then
    info "[dry-run] would close own bump PR #$pr"
  else
    info "Closing own bump PR #$pr (deferring to r-ryantm + merge bot)"
    gh pr close "$pr" --repo "$UPSTREAM" --comment \
      "Closing in favour of the r-ryantm auto-bump + merge-bot flow now that apfel-llm has a maintainer. An open bump PR here would only block r-ryantm from opening its own." \
      >/dev/null 2>&1 || warn "could not close #$pr"
  fi
done

# --- Find the open r-ryantm bump PR for apfel-llm ---
rr_pr=$(gh pr list --repo "$UPSTREAM" --state open --author r-ryantm \
  --search "apfel-llm in:title" --json number,title \
  --jq '.[0] // empty' 2>/dev/null || true)
if [[ -z "$rr_pr" ]]; then
  info "No open r-ryantm PR for apfel-llm yet - it will appear within a day or two of the release; next run handles it."
  exit 0
fi
pr_number=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["number"])' <<<"$rr_pr")
pr_title=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])' <<<"$rr_pr")
info "Found r-ryantm PR #$pr_number: $pr_title"

# --- Extract the version and hash the PR introduces (from its diff) ---
pr_patch=$(gh api "repos/$UPSTREAM/pulls/$pr_number/files" \
  --jq ".[] | select(.filename==\"$PACKAGE_PATH\") | .patch" 2>/dev/null || true)
pr_version=$(grep -E '^\+\s*version = "' <<<"$pr_patch" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
pr_hash=$(grep -E '^\+\s*hash = "' <<<"$pr_patch" | head -1 | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [[ "$pr_version" != "$version" ]]; then
  info "r-ryantm PR bumps to '$pr_version', target is '$version' - not commenting (r-ryantm will advance it, or next release supersedes)"
  exit 0
fi

# --- Verify the PR's SRI hash matches the tarball WE published ---
tarball_url="https://github.com/$APFEL_REPO/releases/download/v${version}/apfel-${version}-arm64-macos.tar.gz"
tmp_tarball=$(mktemp /tmp/apfel-automerge-XXXXXX.tar.gz)
trap 'rm -f "$tmp_tarball"' EXIT
curl -fsSL -o "$tmp_tarball" "$tarball_url" || { warn "could not download $tarball_url"; exit 0; }
if command -v sha256sum >/dev/null 2>&1; then
  hex=$(sha256sum "$tmp_tarball" | awk '{print $1}')
else
  hex=$(shasum -a 256 "$tmp_tarball" | awk '{print $1}')
fi
expected_sri=$(python3 -c "
import base64, sys
raw = bytes.fromhex('$hex')
print('sha256-' + base64.standard_b64encode(raw).decode())
")
if [[ "$pr_hash" != "$expected_sri" ]]; then
  warn "HASH MISMATCH on r-ryantm PR #$pr_number: PR has '$pr_hash', our tarball is '$expected_sri' - NOT merging. Investigate!"
  exit 1
fi
info "Verified: PR version and SRI hash match our published release tarball."

# --- Idempotence: comment the merge command at most once per PR ---
already=$(gh api "repos/$UPSTREAM/issues/$pr_number/comments" \
  --jq "[.[] | select(.user.login==\"$MAINTAINER_LOGIN\") | select(.body | contains(\"nixpkgs-merge-bot merge\"))] | length" 2>/dev/null || echo 0)
if [[ "$already" -gt 0 ]]; then
  info "Merge command already posted on PR #$pr_number - waiting for the bot."
  exit 0
fi

if $dry_run; then
  info "[dry-run] would comment '$MERGE_COMMAND' on PR #$pr_number"
else
  info "Posting merge command on PR #$pr_number..."
  printf '%s' "$MERGE_COMMAND" | python3 -c 'import json,sys; print(json.dumps({"body": sys.stdin.read()}))' \
    | gh api "repos/$UPSTREAM/issues/$pr_number/comments" --input - >/dev/null
  info "Done - merge bot will verify constraints and merge."
fi

info "Done."
