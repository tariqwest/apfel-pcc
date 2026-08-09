# Release Process

## Overview

apfel-plus uses semantic versioning. Releases are fully automated through the local `make release` workflow. Local builds (`make build`, `make install`) never change the version number.

## The release flow

```
make preflight              local qualification (git, build, tests, policy files)
       |
       v pass
make release [TYPE=]        run local release workflow
       |
       v on-device release machine
  bump .version
       |
  build release binary
       |
  unit tests
       |
  integration tests
       |
  stamp CHANGELOG + commit + tag + push
       |
  sign + package tarball + notarize + sha256
       |
  publish GitHub Release
       |
  update Homebrew tap formula
       |
  open nixpkgs bump PR (non-fatal)
       |
       v
./scripts/post-release-verify.sh
```

## Before releasing

```bash
make preflight
```

The preflight script checks:
- Git working tree is clean
- On main branch, up to date with origin
- Release build succeeds
- Unit tests pass
- Integration tests pass
- SECURITY.md, STABILITY.md, LICENSE exist
- Binary version matches .version

Do not release if preflight fails.

Before cutting a release, review whether the branch changes the public `ApfelCore` Swift Package API.

- Additive `ApfelCore` API changes belong in [../CHANGELOG.md](../CHANGELOG.md) and require at least a minor bump.
- Deprecated or removed `ApfelCore` API changes belong in [../CHANGELOG.md](../CHANGELOG.md) and require the deprecation policy from [../STABILITY.md](../STABILITY.md) to be followed.
- Any removal or incompatible signature change to public `ApfelCore` API is a major release.

## Release commands

```bash
make release                    # patch bump (1.0.0 -> 1.0.1)
make release TYPE=minor         # minor bump (1.0.x -> 1.1.0)
make release TYPE=major         # major bump (1.x.y -> 2.0.0)
```

This runs locally via `scripts/publish-release.sh` (not on GitHub Actions - GitHub runners are arm64 VMs without Apple Intelligence and cannot run the full test suite).

## What the release script does

1. Preflight checks (clean tree, on main, up to date with origin)
2. Bumps `.version` via `make release-patch` / `release-minor` / `release-major`
3. Builds the release binary
4. Runs all unit tests via `swift run apfel-plus-tests`
5. Runs all integration tests discovered under `Tests/integration/` with real Apple Intelligence
<<<<<<< HEAD
6. Commits `.version`, `README.md`, `Sources/BuildInfo.swift`, tags, and pushes to main
7. Packages `apfel-plus-<version>-arm64-macos.tar.gz`
8. Publishes GitHub Release with changelog and tarball
9. Updates the Homebrew tap formula (`tariqwest/homebrew-tap`)
=======
6. Stamps the `[Unreleased]` CHANGELOG section as the new version (`scripts/stamp-changelog.sh`), then commits `.version`, `README.md`, `Sources/BuildInfo.swift`, and `CHANGELOG.md`, tags, and pushes to main
7. Signs the binary with the Developer ID identity (hardened runtime) and packages `apfel-<version>-arm64-macos.tar.gz`
8. Verifies the Developer ID signature and notarizes the binary with Apple (hard gate - the release aborts if signing or notarization fails)
9. Publishes the GitHub Release with changelog, the tarball, and an `apfel-<version>-arm64-macos.tar.gz.sha256` checksum asset
10. Updates the Homebrew tap formula (`Arthur-Ficial/homebrew-tap`)
11. Opens a build-verified nixpkgs bump PR (`scripts/publish-nixpkgs-bump.sh`) as a non-fatal final step - a failure here warns but does not fail the release, since the GitHub Release and tap are already published
>>>>>>> upstream/main

Total time: ~5 minutes.

## After releasing

```bash
./scripts/post-release-verify.sh
```

Verifies: GitHub Release exists with tarball, git tag exists, .version matches, installed binary matches, the published `.sha256` asset and Homebrew tap formula agree on the tarball digest, and the shipped binary carries the Developer ID TeamIdentifier (7D2YX5DQ6M).

## Homebrew-core distribution

apfel-plus is in [homebrew-core](https://github.com/Homebrew/homebrew-core). We do NOT maintain the formula directly.

```bash
brew install apfel-plus
brew upgrade apfel-plus
```

- Homebrew's autobump bot picks up new GitHub Releases automatically
- Emergency formula update: `brew bump-formula-pr apfel-plus --url=<tarball-url> --sha256=<hash>`

<<<<<<< HEAD
The release workflow also updates the custom tap (`tariqwest/homebrew-tap`) as a secondary channel for apfel-plus-family tools. The `HOMEBREW_TAP_PUSH_TOKEN` secret is required for tap updates.
=======
`make release` also updates the custom tap (`Arthur-Ficial/homebrew-tap`) as a secondary channel for apfel-family tools, pushing the new formula directly with the active `gh` CLI session (no CI secret involved - releases run locally, not on GitHub Actions).
>>>>>>> upstream/main

## GitHub CI vs local testing

GitHub CI (`ci.yml`) runs on every push/PR as a safety net, but it is a **subset**:
- Unit tests that do not need Apple Intelligence
- Model-free integration checks such as flags, help, version, file handling, man-page drift, the model-free HTTP server suites (CORS/origin/Host/auth/501/OpenAI-shape, servers started in CI), and ApfelCore packaging smoke tests

GitHub CI **cannot** run the full integration suite because GitHub-hosted `macos-26` runners are arm64 VMs without Apple Intelligence. Full qualification runs locally on a Mac with Apple Intelligence via `make preflight` and `make release`. This local run is the real gate - no release ships without it.

## Distribution channels

Each release is published through three channels. All three pull the same tarball from the GitHub Release; nothing is rebuilt per-channel. The `apfel` binary inside is Developer ID signed under a hardened runtime and the submission is notarized by Apple (it is not stapled - a bare CLI binary in a tarball cannot carry a stapled ticket, so Gatekeeper verifies notarization online). A second asset, `apfel-<version>-arm64-macos.tar.gz.sha256`, publishes the checksum independently of the Homebrew formula; `scripts/post-release-verify.sh` cross-checks the tarball digest against both and confirms the Developer ID TeamIdentifier.

| Channel | How fresh | Mechanism |
|---------|-----------|-----------|
<<<<<<< HEAD
| [homebrew-core](https://github.com/Homebrew/homebrew-core/blob/master/Formula/a/apfel-plus.rb) (`brew install apfel-plus`) | Up to ~24h after release | Homebrew `autobump-PR` bot detects new GitHub Releases and opens a formula-bump PR. |
| [tariqwest/homebrew-tap](https://github.com/tariqwest/homebrew-tap) (`brew install tariqwest/tap/apfel-plus`) | Synchronous with release | `scripts/publish-release.sh` pushes the new formula directly as part of `make release`. |
| [nixpkgs](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ap/apfel-plus-llm) (`nix profile install nixpkgs#apfel-plus-llm`) | Within ~7 days | Community [`r-ryantm`](https://github.com/ryantm/nixpkgs-update) bot picks up the new version via the package's `passthru.updateScript`. No release-side action from us. See [nixpkgs.md](nixpkgs.md). |
=======
| [homebrew-core](https://github.com/Homebrew/homebrew-core/blob/master/Formula/a/apfel.rb) (`brew install apfel`) | Up to ~24h after release | Homebrew `autobump-PR` bot detects new GitHub Releases and opens a formula-bump PR. |
| [Arthur-Ficial/homebrew-tap](https://github.com/Arthur-Ficial/homebrew-tap) (`brew install Arthur-Ficial/tap/apfel`) | Synchronous with release | `scripts/publish-release.sh` pushes the new formula directly as part of `make release`. |
| [nixpkgs](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name/ap/apfel-llm) (`nix profile install nixpkgs#apfel-llm`) | Days to weeks | `make release` opens a build-verified bump PR on `NixOS/nixpkgs` (`scripts/publish-nixpkgs-bump.sh`); a committer merges it. `r-ryantm` CANNOT help (darwin-only, Linux-only bot). A twice-daily launchd catch-up (`scripts/nixpkgs-bump-cron.sh`) re-advances the PR and emails Franz if the bump ever fails. See [nixpkgs.md](nixpkgs.md). |
>>>>>>> upstream/main

All three channels are "owned" in the sense that we file PRs against them and respond to reviewer feedback - but merges into homebrew-core and nixpkgs are gated by their respective maintainer communities. The tap is the only channel where we merge directly.

## Versioning rules

apfel-plus follows semver. See [STABILITY.md](../STABILITY.md) for the full stability policy.

- **PATCH** (1.0.x): bug fixes, documentation, CI improvements
- **MINOR** (1.x.0): new flags, new endpoints, backward-compatible features, additive public `ApfelCore` API
- **MAJOR** (x.0.0): removed flags, changed exit codes, breaking API changes, removed or incompatible public `ApfelCore` API

Model output changes from macOS updates are NOT version bumps.

## What triggers a release

- Bug fix merged -> patch
- New flag or endpoint merged -> minor
- Accumulation of small improvements -> patch
- Breaking change to CLI/API contract -> major (update STABILITY.md)

## What does NOT trigger a release

- Docs-only changes (commit to main, no release needed)
- CI/workflow changes (commit to main, no release needed)
- Test-only changes (commit to main, no release needed)

## What NOT to do

- Do not run `bump-patch`, `bump-minor`, `bump-major` directly
- Do not manually edit `.version`, `BuildInfo.swift`, or the README badge
- Do not create git tags manually
- Do not run `gh release create` manually
- Do not push to the Homebrew tap manually (the workflow handles it)
- Do not run `make package-release-asset` outside the workflow
