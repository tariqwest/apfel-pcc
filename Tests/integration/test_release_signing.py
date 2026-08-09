"""
apfel Integration Tests - release signing / notarization wiring (static).

#226: the shipped tarball was only ad-hoc signed (flags=adhoc, no
TeamIdentifier) and no checksum was published as a release asset, while
CLAUDE.md/docs claimed a "signed tarball". These grep-based tests assert the
release plumbing now:

- signs the binary with the Developer ID identity under a hardened runtime
  (`--options runtime`) before tarring,
- notarizes the signed binary as a hard gate on the release path,
- publishes an `apfel-<v>-arm64-macos.tar.gz.sha256` checksum asset,
- verifies the checksum and the Developer ID TeamIdentifier post-release,
- and that the docs no longer falsely claim the plain tarball is signed.

They do not run codesign/notarytool (that needs the private key + Apple's
service); the live signing verification is done by the release operator and
recorded in the task report.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
MAKEFILE = (ROOT / "Makefile").read_text()
PUBLISH = (ROOT / "scripts" / "publish-release.sh").read_text()
VERIFY = (ROOT / "scripts" / "post-release-verify.sh").read_text()
CLAUDE = (ROOT / "CLAUDE.md").read_text()

TEAM_ID = "7D2YX5DQ6M"
IDENTITY = f"Developer ID Application: Franz Enzenhofer ({TEAM_ID})"


def test_release_signs_with_developer_id_and_hardened_runtime():
    # The release path must codesign with the Developer ID identity and the
    # hardened runtime option (required for notarization) before packaging.
    # Signing lives in publish-release.sh (not package-release-asset) so plain
    # dev/CI packaging never touches the keychain.
    assert "codesign" in PUBLISH, "release path must codesign the binary (#226)"
    assert IDENTITY in PUBLISH, f"must sign with '{IDENTITY}' (#226)"
    assert "--options runtime" in PUBLISH, (
        "must sign with a hardened runtime (--options runtime) so the binary "
        "can be notarized (#226)"
    )
    # package-release-asset must stay signing-free (used by make test / CI).
    assert "codesign" not in MAKEFILE, (
        "package-release-asset must not codesign - that would prompt the "
        "keychain during `make test`/CI (#226)"
    )


def test_release_path_notarizes_as_a_hard_gate():
    assert "notarytool submit" in PUBLISH, (
        "publish-release.sh must submit the signed binary to notarytool (#226)"
    )
    assert "--wait" in PUBLISH, "notarytool submit must --wait for the result (#226)"
    # The release path must verify the binary is Developer ID signed (not adhoc).
    assert TEAM_ID in PUBLISH, (
        "publish-release.sh must assert the Developer ID TeamIdentifier "
        f"{TEAM_ID} before publishing (#226)"
    )


def test_release_publishes_sha256_checksum_asset():
    assert ".sha256" in PUBLISH, (
        "publish-release.sh must produce a .sha256 checksum sidecar (#226)"
    )
    # Both the tarball and the checksum must be uploaded to the release.
    assert 'gh release create "v$version" "$asset" "$asset.sha256"' in PUBLISH or (
        'gh release upload "v$version" "$asset" "$asset.sha256"' in PUBLISH
    ), "publish-release.sh must upload the .sha256 asset alongside the tarball (#226)"


def test_post_release_verifies_checksum_and_team_identifier():
    assert ".sha256" in VERIFY, (
        "post-release-verify.sh must verify the published .sha256 asset (#226)"
    )
    assert TEAM_ID in VERIFY, (
        "post-release-verify.sh must verify the Developer ID TeamIdentifier "
        f"{TEAM_ID} via codesign (#226)"
    )
    assert "codesign" in VERIFY, (
        "post-release-verify.sh must run codesign on the downloaded binary (#226)"
    )


def test_claude_md_no_longer_falsely_claims_plain_signed_tarball():
    # The old wording "same signed tarball" over-claimed. The corrected text
    # must mention notarization (the real, verifiable state).
    assert "notariz" in CLAUDE.lower(), (
        "CLAUDE.md must describe the tarball as Developer ID signed AND "
        "notarized, not just 'signed' (#226)"
    )
