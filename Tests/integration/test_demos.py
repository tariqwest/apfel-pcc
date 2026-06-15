"""
apfel-plus Integration Tests - `apfel-plus demos` and the embedded-demo generator.

The demos are embedded in the binary (Sources/Core/GeneratedDemos.swift) so
`apfel-plus demos <dir>` behaves identically on homebrew-core, the tap, and source
builds - there is no brew `--with-demo` option that could (core forbids
options). These tests assert the generated file stays in sync with demo/ and
that the built binary actually writes the demos out.

Run: python3 -m pytest Tests/integration/test_demos.py -v
"""

import base64
import pathlib
import re
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DEMO_DIR = ROOT / "demo"
GENERATED = ROOT / "Sources" / "Core" / "GeneratedDemos.swift"
GENERATOR = ROOT / "scripts" / "generate-demos.sh"
BINARY = ROOT / ".build" / "release" / "apfel-plus"
DEBUG_BINARY = ROOT / ".build" / "debug" / "apfel-plus"


def _binary() -> pathlib.Path | None:
    candidates = [b for b in (BINARY, DEBUG_BINARY) if b.exists()]
    if not candidates:
        return None
    # Prefer the most recently built binary (a stale release build may predate
    # the feature under test).
    return max(candidates, key=lambda b: b.stat().st_mtime)


def _embedded() -> dict[str, bytes]:
    """Parse name -> decoded bytes out of the generated Swift file."""
    text = GENERATED.read_text()
    out: dict[str, bytes] = {}
    for m in re.finditer(
        r'EmbeddedDemo\(name: "([^"]+)", isExecutable: \w+, base64: "([^"]*)"\)',
        text,
    ):
        out[m.group(1)] = base64.b64decode(m.group(2))
    return out


def test_generated_file_exists():
    assert GENERATED.exists(), "Sources/Core/GeneratedDemos.swift missing - run make generate-demos"


def test_generated_embeds_every_demo_file_byte_for_byte():
    embedded = _embedded()
    for path in sorted(DEMO_DIR.iterdir()):
        if not path.is_file():
            continue
        assert path.name in embedded, f"demo/{path.name} not embedded - run make generate-demos"
        assert embedded[path.name] == path.read_bytes(), (
            f"embedded demo {path.name} is out of sync with demo/{path.name} - run make generate-demos"
        )


def test_generated_file_has_no_extra_entries():
    embedded = set(_embedded())
    on_disk = {p.name for p in DEMO_DIR.iterdir() if p.is_file()}
    assert embedded == on_disk, (
        f"generated demos {embedded} differ from demo/ {on_disk} - run make generate-demos"
    )


def test_generator_is_idempotent():
    """Running the generator must not change the committed file (no drift)."""
    before = GENERATED.read_bytes()
    subprocess.run(["bash", str(GENERATOR)], cwd=ROOT, check=True, capture_output=True)
    after = GENERATED.read_bytes()
    assert before == after, "make generate-demos changed the file - commit the regenerated output"


def test_apfel_demos_writes_executable_scripts(tmp_path):
    binary = _binary()
    if binary is None:
        pytest.skip("apfel-plus binary not built (run `swift build`)")
    target = tmp_path / "demos"
    result = subprocess.run(
        [str(binary), "demos", str(target)], capture_output=True, text=True
    )
    assert result.returncode == 0, f"apfel-plus demos failed: {result.stderr}"
    cmd = target / "cmd"
    assert cmd.exists(), "apfel-plus demos did not write cmd"
    assert cmd.stat().st_mode & 0o111, "cmd is not executable after apfel-plus demos"
    # Byte-for-byte fidelity with the source.
    assert cmd.read_bytes() == (DEMO_DIR / "cmd").read_bytes()
