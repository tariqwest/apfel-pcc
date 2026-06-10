"""
apfel-plus Integration Tests - scripts/bump-nixpkgs.sh.

The bump-nixpkgs.sh script is a pure shell tool that updates apfel-plus-llm's
package.nix in a nixpkgs checkout. It must:
  - rewrite version and hash exactly once each
  - compute a correct SRI sha256 from a local tarball
  - be idempotent (no-op when already at target)
  - support --dry-run (no file mutation)

These tests use synthetic fixtures and require no network or nix tooling
beyond python3 + sha256sum/shasum.
"""

import base64
import hashlib
import pathlib
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "bump-nixpkgs.sh"

PACKAGE_TEMPLATE = """{
  lib,
  stdenv,
  fetchurl,
  versionCheckHook,
  nix-update-script,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "apfel-plus-llm";
  version = "1.0.5";

  src = fetchurl {
    url = "https://example.com/apfel-plus-${finalAttrs.version}.tar.gz";
    hash = "sha256-etEOYkYVPm08SRE3nuKcDigS7lCkUUgMacOl/sLv/1A=";
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    runHook postInstall
  '';
})
"""


def _run(args, **kwargs):
    """Run a command; return (returncode, stdout, stderr)."""
    proc = subprocess.run(
        args,
        capture_output=True,
        text=True,
        **kwargs,
    )
    return proc.returncode, proc.stdout, proc.stderr


def _expected_sri(tarball: pathlib.Path) -> str:
    raw = hashlib.sha256(tarball.read_bytes()).digest()
    return "sha256-" + base64.standard_b64encode(raw).decode()


@pytest.fixture
def workspace(tmp_path):
    """Synthetic package.nix + a deterministic 'tarball' on disk."""
    pkg = tmp_path / "package.nix"
    pkg.write_text(PACKAGE_TEMPLATE)

    tarball = tmp_path / "apfel-plus-1.3.3-arm64-macos.tar.gz"
    tarball.write_bytes(b"deterministic-fake-tarball-bytes-for-test\n")

    return pkg, tarball


def test_script_is_executable():
    assert SCRIPT.exists(), f"missing: {SCRIPT}"
    assert (SCRIPT.stat().st_mode & 0o111), "bump-nixpkgs.sh is not executable"


def test_bump_rewrites_version_and_hash(workspace):
    pkg, tarball = workspace
    expected_hash = _expected_sri(tarball)

    rc, out, err = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(pkg),
        "--tarball", str(tarball),
    ])

    assert rc == 0, f"non-zero exit: {rc}\nstdout: {out}\nstderr: {err}"

    text = pkg.read_text()
    assert 'version = "1.3.3";' in text
    assert f'hash = "{expected_hash}";' in text
    # old values are gone
    assert 'version = "1.0.5";' not in text
    assert "etEOYkYVPm08" not in text


def test_bump_is_idempotent(workspace):
    pkg, tarball = workspace

    # first bump - changes the file
    rc1, _, _ = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(pkg),
        "--tarball", str(tarball),
    ])
    assert rc1 == 0
    after_first = pkg.read_text()

    # second bump with same inputs - exits 0 with no change message
    rc2, _, err2 = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(pkg),
        "--tarball", str(tarball),
    ])
    assert rc2 == 0, f"second run should be idempotent, got rc={rc2}, stderr={err2}"
    assert "no change" in err2.lower()
    assert pkg.read_text() == after_first


def test_dry_run_does_not_modify_file(workspace):
    pkg, tarball = workspace
    before = pkg.read_text()

    rc, out, err = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(pkg),
        "--tarball", str(tarball),
        "--dry-run",
    ])

    assert rc == 0, f"non-zero exit: {rc}\nstderr: {err}"
    # File must be unchanged
    assert pkg.read_text() == before
    # Diff output should mention the new version somewhere
    assert "1.3.3" in out or "1.3.3" in err


def test_missing_required_args_fails(tmp_path):
    rc, _, _ = _run([str(SCRIPT)])
    assert rc != 0

    rc, _, _ = _run([str(SCRIPT), "--version", "1.3.3"])
    assert rc != 0

    rc, _, _ = _run([str(SCRIPT), "--file", str(tmp_path / "x.nix")])
    assert rc != 0


def test_nonexistent_file_fails(tmp_path):
    rc, _, err = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(tmp_path / "does-not-exist.nix"),
        "--tarball", str(tmp_path / "fake.tar.gz"),
    ])
    assert rc != 0
    assert "not found" in err.lower()


def test_version_only_changes_first_match(workspace):
    """version regex must use count=1 - if package.nix grew a second 'version =' line, only the first is touched."""
    pkg, tarball = workspace
    # add a fake second version line lower in the file
    text = pkg.read_text() + '\n  meta.someAttr = { version = "9.9.9"; };\n'
    pkg.write_text(text)

    rc, _, _ = _run([
        str(SCRIPT),
        "--version", "1.3.3",
        "--file", str(pkg),
        "--tarball", str(tarball),
    ])
    assert rc == 0

    new_text = pkg.read_text()
    assert 'version = "1.3.3";' in new_text
    # the second version line must remain untouched
    assert 'version = "9.9.9";' in new_text
