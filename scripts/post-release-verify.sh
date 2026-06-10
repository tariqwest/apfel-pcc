#!/usr/bin/env bash
# Post-release verification for apfel.
# Run after the Publish Release workflow completes.
# Usage: ./scripts/post-release-verify.sh [expected-version]
set -euo pipefail

version="${1:-$(cat .version)}"

step() { echo ""; echo "=== $1 ==="; }
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }
FAILED=0

# --- 1. GitHub Release exists ---
step "GitHub Release"
if gh release view "v$version" --repo Arthur-Ficial/apfel >/dev/null 2>&1; then
    pass "v$version release exists"
    # Check tarball asset
    if gh release view "v$version" --repo Arthur-Ficial/apfel --json assets --jq '.assets[].name' | grep -q "apfel-$version-arm64-macos.tar.gz"; then
        pass "tarball asset attached"
    else
        fail "tarball asset missing from release"
    fi
else
    fail "v$version release not found on GitHub"
fi

# --- 2. Git tag exists ---
step "Git tag"
git fetch --tags origin
if git tag -l "v$version" | grep -q "v$version"; then
    pass "tag v$version exists"
else
    fail "tag v$version not found"
fi

# --- 3. .version matches ---
step "Version file"
file_v=$(cat .version)
if [ "$file_v" = "$version" ]; then
    pass ".version = $version"
else
    fail ".version = $file_v, expected $version"
fi

# --- 4. Installed binary ---
step "Installed binary"
if command -v apfel >/dev/null 2>&1; then
    installed_v=$(apfel --version 2>&1 | head -1)
    echo "Installed: $installed_v"
    if echo "$installed_v" | grep -q "$version"; then
        pass "installed binary matches"
    else
        echo "(Mismatch is OK if you haven't run brew upgrade yet)"
    fi
else
    echo "apfel not in PATH (install with: brew install apfel-plus)"
fi

# --- 5. Homebrew (informational) ---
step "Homebrew (informational)"
echo "homebrew-core autobump is async - may take up to 24h."
echo "Check: brew info apfel"
echo "Manual bump: brew bump-formula-pr apfel-plus --url=<tarball-url> --sha256=<hash>"

# --- Summary ---
step "Summary"
if [ "$FAILED" -eq 0 ]; then
    echo "Release v$version verified successfully."
else
    echo "Some checks failed. Review output above."
    exit 1
fi
