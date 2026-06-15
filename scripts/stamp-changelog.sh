#!/usr/bin/env bash
# stamp-changelog.sh - move the accumulated [Unreleased] section into a dated
# version heading and open a fresh empty [Unreleased] above it.
#
# Keep a Changelog convention: developers add entries under "## [Unreleased]"
# during development; the release stamps that section as the new version. This
# is what keeps CHANGELOG.md current at release time (see #201) instead of
# drifting (it had stalled at 1.0.5 because the release flow never touched it).
#
# Idempotent: if the target version is already present, it does nothing.
#
# Usage:
#   ./scripts/stamp-changelog.sh <version> [<date>] [<file>]
#     date defaults to today (UTC, YYYY-MM-DD); file defaults to CHANGELOG.md
set -euo pipefail

version="${1:?usage: stamp-changelog.sh <version> [date] [file]}"
date="${2:-$(date -u +%Y-%m-%d)}"
file="${3:-CHANGELOG.md}"

[ -f "$file" ] || { echo "stamp-changelog: $file not found" >&2; exit 1; }

ver_re="^## \[${version//./\\.}\]"
if grep -qE "$ver_re" "$file"; then
  echo "stamp-changelog: $file already documents [$version] - nothing to do"
  exit 0
fi

if ! grep -qE '^## \[Unreleased\]' "$file"; then
  echo "stamp-changelog: no '## [Unreleased]' heading in $file - cannot stamp" >&2
  exit 1
fi

tmp=$(mktemp)
awk -v ver="$version" -v dt="$date" '
  /^## \[Unreleased\]/ && !done {
    print
    print ""
    print "## [" ver "] - " dt
    done = 1
    next
  }
  { print }
' "$file" > "$tmp"
mv "$tmp" "$file"
echo "stamp-changelog: stamped [$version] - $date in $file"
