#!/usr/bin/env bash
# check-changelog.sh - fail if a change touches production source without a
# CHANGELOG.md [Unreleased] entry.
#
# This is the permanent guard against the empty-[Unreleased] release gate:
# scripts/stamp-changelog.sh (gate #263) hard-aborts a release when the
# [Unreleased] section is empty, so a code fix that merges changelog-less
# blocks the very next release (this is exactly what stalled v1.8.1 - #368
# merged with no changelog entry). This gate moves that enforcement from
# release time to merge time, in CI on every pull request (#369).
#
# "Production source" = Sources/** minus the generated Sources/BuildInfo.swift.
# Docs-only, test-only, and build-info-only changes do not require an entry.
# The [Unreleased] content definition matches stamp-changelog.sh exactly so the
# two gates never disagree.
#
# Usage: check-changelog.sh [base-ref]
#   base-ref defaults to origin/main. The comparison is merge-base(base, HEAD)
#   ..HEAD, i.e. only what this branch changed since it diverged from base.
set -euo pipefail

base="${1:-origin/main}"
file="CHANGELOG.md"

if [ ! -f "$file" ]; then
  echo "check-changelog: $file not found - run from the repo root" >&2
  exit 1
fi

# Resolve the merge base so we only inspect what THIS branch introduced. If it
# cannot be resolved (e.g. an unrelated shallow clone) fail open rather than
# block spuriously - CI fetches the base branch so this path should not hit.
if ! merge_base=$(git merge-base "$base" HEAD 2>/dev/null); then
  echo "check-changelog: cannot resolve merge-base with '$base' - skipping." >&2
  exit 0
fi

changed=$(git diff --name-only "$merge_base" HEAD)

prod=$(printf '%s\n' "$changed" \
  | grep -E '^Sources/' \
  | grep -vE '^Sources/BuildInfo\.swift$' \
  || true)

if [ -z "$prod" ]; then
  echo "check-changelog: no production source changes - CHANGELOG entry not required."
  exit 0
fi

# A "content line" is any non-blank line inside [Unreleased] that is not a
# '### Subheading' - identical to stamp-changelog.sh's definition (#263).
content=$(awk '
  /^## \[Unreleased\]/ { insection = 1; next }
  insection && /^## / { exit }
  insection {
    if ($0 ~ /^[[:space:]]*$/) next
    if ($0 ~ /^### /) next
    print
  }
' "$file")

if [ -z "$content" ]; then
  {
    echo "::error::Production source changed but CHANGELOG.md '## [Unreleased]' has no entry."
    echo "Add an Added/Fixed/Changed bullet under [Unreleased] before merging."
    echo "This blocks the next release at stamp-changelog.sh (gate #263, root cause #369)."
    echo "Changed production files:"
    printf '  %s\n' $prod
  } >&2
  exit 1
fi

echo "check-changelog: production source changed and [Unreleased] has content - OK."
