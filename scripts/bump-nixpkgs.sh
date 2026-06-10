#!/usr/bin/env bash
#
# bump-nixpkgs.sh - update apfel-plus-llm/package.nix version and hash.
#
# Does NOT touch git or gh; callers (GitHub Actions workflow, humans)
# drive commit/push/PR separately. This keeps the script deterministic
# and unit-testable.
#
# Usage:
#   scripts/bump-nixpkgs.sh --version X.Y.Z --file path/to/package.nix \
#       [--tarball path/to/local.tar.gz] [--dry-run]
#
# If --tarball is omitted, the script downloads
#   https://github.com/Arthur-Ficial/apfel/releases/download/vX.Y.Z/apfel-X.Y.Z-arm64-macos.tar.gz
#
# --dry-run prints the would-be diff and does not modify the target file.

set -euo pipefail

version=""
file=""
tarball=""
dry_run=false

usage() {
  echo "usage: $0 --version <x.y.z> --file <path/to/package.nix> [--tarball <local.tar.gz>] [--dry-run]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   version="${2:-}"; shift 2 ;;
    --file)      file="${2:-}"; shift 2 ;;
    --tarball)   tarball="${2:-}"; shift 2 ;;
    --dry-run)   dry_run=true; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage; exit 1 ;;
  esac
done

if [[ -z "$version" || -z "$file" ]]; then
  usage
  exit 1
fi

if [[ ! -f "$file" ]]; then
  echo "error: file not found: $file" >&2
  exit 1
fi

# Acquire the tarball -- either given locally or downloaded to a tempdir.
tmpdir=""
cleanup() {
  if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
    rm -rf "$tmpdir"
  fi
  return 0
}
trap cleanup EXIT

if [[ -z "$tarball" ]]; then
  tmpdir=$(mktemp -d)
  tarball="$tmpdir/apfel-${version}-arm64-macos.tar.gz"
  url="https://github.com/Arthur-Ficial/apfel/releases/download/v${version}/apfel-${version}-arm64-macos.tar.gz"
  echo "downloading: $url" >&2
  if ! curl -sSfL -o "$tarball" "$url"; then
    echo "error: failed to download $url" >&2
    exit 1
  fi
fi

if [[ ! -f "$tarball" ]]; then
  echo "error: tarball not found: $tarball" >&2
  exit 1
fi

# Compute SRI-format sha256 hash: "sha256-<base64(raw-sha256)>".
# Prefer sha256sum (Linux, nix runners); fall back to shasum (macOS).
if command -v sha256sum >/dev/null 2>&1; then
  hex=$(sha256sum "$tarball" | awk '{print $1}')
else
  hex=$(shasum -a 256 "$tarball" | awk '{print $1}')
fi
if [[ -z "$hex" ]]; then
  echo "error: failed to compute sha256" >&2
  exit 1
fi

# hex -> raw bytes -> base64. Use python3 (ubiquitous and deterministic).
sri=$(python3 -c "
import base64, sys
raw = bytes.fromhex('$hex')
print('sha256-' + base64.standard_b64encode(raw).decode())
")

if [[ ! "$sri" =~ ^sha256- ]]; then
  echo "error: failed to compute SRI hash" >&2
  exit 1
fi

# Rewrite only `version = "..."` and `hash = "sha256-..."` in place.
# Python writes directly to the file so the original trailing newline is preserved
# byte-for-byte (treefmt rejects nixpkgs files without a final newline).
# `$dry_run` is consumed inside python so the script stays single-pass.
python3 - "$file" "$version" "$sri" "$dry_run" <<'PY'
import pathlib, re, sys
path, new_version, new_hash, dry_run = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = pathlib.Path(path).read_text()
dst = re.sub(r'version = "[^"]*";', f'version = "{new_version}";', src, count=1)
dst = re.sub(r'hash = "sha256-[^"]*";', f'hash = "{new_hash}";', dst, count=1)
if dst == src:
    print("no change: version and hash already current", file=sys.stderr)
    sys.exit(0)
if dry_run == "true":
    import difflib
    sys.stderr.writelines(difflib.unified_diff(
        src.splitlines(keepends=True), dst.splitlines(keepends=True),
        fromfile=f"{path} (current)", tofile=f"{path} (would be)"))
    print("\n(dry-run: file not modified)", file=sys.stderr)
    sys.exit(0)
pathlib.Path(path).write_text(dst)
PY

echo "updated $file -> version=$version hash=$sri" >&2
