#!/usr/bin/env bash
# Post-release verification for apfel.
# Run after `make release` (scripts/publish-release.sh) completes.
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

# --- 4b. Checksum + signature integrity (#226) ---
step "Checksum + Developer ID signature"
tarball="apfel-$version-arm64-macos.tar.gz"
work=$(mktemp -d)
if gh release download "v$version" --repo Arthur-Ficial/apfel \
        --pattern "$tarball" --pattern "$tarball.sha256" --dir "$work" 2>/dev/null; then
    # (a) tarball digest must match the published .sha256 asset
    if [ -f "$work/$tarball.sha256" ]; then
        published=$(awk '{print $1}' "$work/$tarball.sha256")
        actual=$(shasum -a 256 "$work/$tarball" | awk '{print $1}')
        if [ "$published" = "$actual" ]; then
            pass "tarball digest matches published .sha256 asset"
        else
            fail "tarball digest ($actual) != published .sha256 ($published)"
        fi
    else
        fail ".sha256 checksum asset missing from release"
    fi

    # (b) tarball digest must match the Homebrew tap formula sha256
    formula=$(curl -fsSL "https://raw.githubusercontent.com/Arthur-Ficial/homebrew-tap/main/Formula/apfel.rb" 2>/dev/null || true)
    tap_sha=$(printf '%s\n' "$formula" | grep -oE 'sha256 "[0-9a-f]{64}"' | head -1 | grep -oE '[0-9a-f]{64}')
    actual=$(shasum -a 256 "$work/$tarball" | awk '{print $1}')
    if [ -n "$tap_sha" ]; then
        if [ "$tap_sha" = "$actual" ]; then
            pass "tarball digest matches Homebrew tap formula sha256"
        else
            fail "tarball digest ($actual) != tap formula sha256 ($tap_sha)"
        fi
    else
        echo "(could not read tap formula sha256 - skipping tap comparison)"
    fi

    # (c) the shipped binary must carry the Developer ID TeamIdentifier
    tar -C "$work" -xzf "$work/$tarball" apfel 2>/dev/null || true
    if [ -f "$work/apfel" ]; then
        sig=$(codesign -dvv "$work/apfel" 2>&1 || true)
        if echo "$sig" | grep -q "TeamIdentifier=7D2YX5DQ6M"; then
            pass "binary is Developer ID signed (TeamIdentifier=7D2YX5DQ6M)"
        else
            fail "binary is not Developer ID signed (TeamIdentifier 7D2YX5DQ6M not found)"
        fi
    else
        fail "could not extract apfel binary from tarball"
    fi
else
    fail "could not download release assets for v$version"
fi
rm -rf "$work"

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
