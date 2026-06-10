# nixpkgs distribution

apfel-plus ships on [nixpkgs](https://github.com/NixOS/nixpkgs) under the attribute `apfel-plus-llm`. This page covers the install, the name choice, and how new versions land upstream.

## Install (end users)

```bash
nix profile install nixpkgs#apfel-plus-llm
```

Runtime requirements are the same as Homebrew: macOS 26 Tahoe or later, Apple Silicon, Apple Intelligence enabled, Siri language matching device language.

The binary on your `$PATH` is still `apfel-plus` - only the install-time attribute is `apfel-plus-llm`.

## Why `apfel-plus-llm` and not `apfel-plus`

nixpkgs already has an unrelated package at [`pkgs/by-name/ap/apfel-plus`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ap/apfel-plus/package.nix): the [scarrazza/apfel-plus](https://github.com/scarrazza/apfel-plus) particle-physics PDF Evolution Library (GPL3, maintained by `veprbl`). The name was taken years before apfel-plus existed in its AI form, so nixpkgs convention requires disambiguation.

The disambiguator that landed upstream is `apfel-plus-llm` (via [NixOS/nixpkgs#508084](https://github.com/NixOS/nixpkgs/pull/508084)). The binary on `$PATH` is still `apfel-plus` either way - only the install attribute differs.

## Why a pre-built binary derivation

apfel-plus links against Apple's [`FoundationModels`](https://developer.apple.com/documentation/foundationmodels) framework, which requires the macOS 26 SDK and Apple Silicon at build time. The nixpkgs darwin stdenv does not currently ship those prerequisites, so building from source inside a Nix sandbox is not reliably supported today.

The derivation installs the same signed release tarball that Homebrew consumes (`apfel-plus-${version}-arm64-macos.tar.gz` attached to each GitHub Release), and declares `sourceProvenance = [ binaryNativeCode ]` to be honest about that.

If nixpkgs' darwin stdenv later gains macOS 26 SDK support, we switch to a source build in a follow-up PR.

## How new versions land

There are two eras, and `scripts/publish-nixpkgs-bump.sh` (run as the final, non-fatal step of `make release`) switches between them automatically by checking whether `arthurficial` is listed in `meta.maintainers` on nixpkgs master.

### Maintainer era (target state - fully zero-touch)

Once [NixOS/nixpkgs#524394](https://github.com/NixOS/nixpkgs/pull/524394) lands, nobody touches anything:

1. **[`r-ryantm`](https://github.com/ryantm/nixpkgs-update)** (the official nixpkgs update bot) opens a bump PR within a day or two of each GitHub Release, via `passthru.updateScript = nix-update-script { }`.
2. **`scripts/nixpkgs-automerge.sh`** finds that PR, verifies its version and SRI hash against the tarball we actually published, and comments **`@NixOS/nixpkgs-merge-bot merge`**. The [merge bot](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md#nixpkgs-merge-bot) merges `pkgs/by-name/*` PRs opened by r-ryantm when the commenter maintains all touched packages and CI is green.
3. The script runs twice daily via launchd (`~/Library/LaunchAgents/com.arthurficial.apfel-nixpkgs-automerge.plist`, logs at `~/Library/Logs/apfel-nixpkgs-automerge.log`) and once immediately as part of `make release`. It is idempotent and self-healing: it also accepts the pending NixOS org invite (required for merge-bot eligibility) and closes any legacy bump PRs of ours, which would otherwise block r-ryantm from opening its own.

The merge bot only acts on PRs opened by r-ryantm or committers - our own bump PRs can never use it. That is why the maintainer era defers to r-ryantm entirely instead of opening our own PR.

### Pre-maintainer era (legacy - active until #524394 merges)

1. **`make release`** runs `scripts/publish-nixpkgs-bump.sh` after the GitHub Release and Homebrew tap are updated. The script forks `NixOS/nixpkgs` to `tariqwest/nixpkgs` (one-time), syncs from upstream master, edits `pkgs/by-name/ap/apfel-plus-llm/package.nix`, pushes, and opens a PR on `NixOS/nixpkgs`. Idempotent at every layer (fork, branch, PR), and **non-fatal**: a bump failure does not fail the release.
2. **r-ryantm** and **community contributors** are the safety net if the local script is skipped.

### One advancing PR, not one per release

Each run reuses the existing open apfel-plus-llm bump PR (it force-pushes the same branch, which updates that PR in place) and closes any stragglers, so there is always **exactly one** open bump PR pointing at the latest version. Earlier the branch name embedded the version (`apfel-plus-llm-${VERSION}`), so every release opened a fresh PR and they piled up unmerged (1.3.5 / 1.3.6 / 1.3.7 / 1.3.8 were all open at once). The dedup is scoped to bump branches (`apfel-plus-llm-bump` and `apfel-plus-llm-<version>`); non-bump PRs such as `apfel-plus-llm-add-maintainer` are never touched.

### Why nixpkgs lags in the pre-maintainer era

The bump automation is not the bottleneck - it opens a correct PR on every release. The lag is **merge latency**: only nixpkgs committers can merge, and a version bump for an unmaintained, darwin-only package sits in the general queue for days to weeks. The maintainer era above removes that wait. Treat nixpkgs as the slower channel regardless: Homebrew (`brew install apfel-plus`, autobumped) and the [tariqwest tap](https://github.com/tariqwest/homebrew-tap) (pushed synchronously by `make release`) are the fast paths we fully control.

### Why the bump runs locally, not in GitHub Actions

We tried a release-triggered GitHub Actions workflow (`.github/workflows/bump-nixpkgs.yml`, ripped out in commit 77dd322) and it didn't work cleanly: opening a PR on `NixOS/nixpkgs` requires a classic PAT with `public_repo` scope, fine-grained tokens cannot do cross-org `createPullRequest`, and pushing to the fork's `.github/workflows/` requires extra `workflow` scope. That's a long-lived secret + scope expansion we didn't want.

`make release` already runs locally (GitHub-hosted runners lack Apple Intelligence). Locally we have an interactive `gh auth login` session for the Arthur-Ficial account with full cross-org PR scope. No stored credential, no workflow-scope hack - just call `gh` from the script.

## Running the bump on its own

```bash
./scripts/publish-nixpkgs-bump.sh                   # uses .version
./scripts/publish-nixpkgs-bump.sh --version 1.3.3   # explicit (catch-up bumps)
./scripts/publish-nixpkgs-bump.sh --dry-run         # no fork/push/PR
```

In the maintainer era this defers to the automerge reconciler, which can also be run directly:

```bash
./scripts/nixpkgs-automerge.sh                      # target = latest GitHub release
./scripts/nixpkgs-automerge.sh --version 1.5.3      # explicit target
./scripts/nixpkgs-automerge.sh --dry-run            # report, change nothing
```

Prerequisites: `nix` (for `nix-prefetch-url`), `gh` CLI logged into Arthur-Ficial, `python3`, `git`. The script verifies these and skips with a warning if anything is missing - it never blocks the release.

The fork `Arthur-Ficial/nixpkgs` is created on first run via `gh repo fork`. The local checkout lives at `~/dev/nixpkgs-bump` (override with `NIXPKGS_BUMP_DIR`).

## Manual self-bump (recovery, if the script breaks)

On any machine with `nix` and `git`:

```bash
git clone --depth 1 https://github.com/NixOS/nixpkgs.git /tmp/nixpkgs-bump
cd /tmp/nixpkgs-bump

# Fork NixOS/nixpkgs to your account first via the GitHub UI, then:
git remote add fork git@github.com:YOUR_USER/nixpkgs.git

VERSION="X.Y.Z"   # e.g. 1.3.4
URL="https://github.com/Arthur-Ficial/apfel/releases/download/v${VERSION}/apfel-plus-${VERSION}-arm64-macos.tar.gz"
HASH=$(nix-prefetch-url --type sha256 "$URL" | xargs nix-hash --to-sri --type sha256)

git checkout -b "apfel-plus-llm-${VERSION}"
sed -i.bak -E "s/version = \"[^\"]+\"/version = \"${VERSION}\"/; s|hash = \"sha256-[^\"]+\"|hash = \"${HASH}\"|" \
  pkgs/by-name/ap/apfel-plus-llm/package.nix
rm pkgs/by-name/ap/apfel-plus-llm/package.nix.bak

git add pkgs/by-name/ap/apfel-plus-llm/package.nix
git commit -m "apfel-plus-llm: ${VERSION}"
git push fork "apfel-plus-llm-${VERSION}"

gh pr create --repo NixOS/nixpkgs \
  --head "YOUR_USER:apfel-plus-llm-${VERSION}" \
  --base master \
  --title "apfel-plus-llm: ${VERSION}" \
  --body "Routine version bump."
```

## Testing the package locally

```bash
git clone --depth 1 https://github.com/NixOS/nixpkgs.git /tmp/nixpkgs-test
cd /tmp/nixpkgs-test
nix-build -A apfel-plus-llm --no-out-link

ls /nix/store/*-apfel-plus-llm-*/bin/apfel-plus
```

Run it: `/nix/store/...-apfel-plus-llm-.../bin/apfel-plus --version`.

## Tracking

- Package source: <https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ap/apfel-plus-llm/package.nix>
- nixpkgs PRs: <https://github.com/NixOS/nixpkgs/pulls?q=is%3Apr+apfel-plus-llm>
- r-ryantm PRs for apfel-plus-llm: <https://github.com/NixOS/nixpkgs/pulls/r-ryantm?q=apfel-plus-llm>
