"""
apfel Integration Tests -- CHANGELOG [Unreleased] merge gate

Model-free: spins throwaway git repos and drives scripts/check-changelog.sh.

Guards #369 (root cause of the v1.8.1 stall): a PR that changes production
source (Sources/**, excluding the generated BuildInfo.swift) must carry a
non-empty CHANGELOG.md [Unreleased] entry. Without this, a code fix merges
changelog-less and then hard-blocks the very next release at stamp-changelog.sh
(gate #263). This gate moves that enforcement from release time to merge time.

Run: python3 -m pytest Tests/integration/test_changelog_gate.py -v
"""

import subprocess
import pathlib

REPO_ROOT = pathlib.Path(__file__).parent.parent.parent
SCRIPT = REPO_ROOT / "scripts" / "check-changelog.sh"

CHANGELOG_EMPTY = """\
# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01

### Added

- Initial release.
"""

CHANGELOG_WITH_ENTRY = """\
# Changelog

## [Unreleased]

### Fixed

- A real user-facing fix worth documenting.

## [1.0.0] - 2026-01-01

### Added

- Initial release.
"""


def _git(repo, *args):
    subprocess.run(["git", *args], cwd=repo, check=True,
                   capture_output=True, text=True)


def _init_repo(tmp_path, changelog):
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q", "-b", "main")
    _git(repo, "config", "user.email", "test@example.com")
    _git(repo, "config", "user.name", "Test")
    (repo / "CHANGELOG.md").write_text(changelog)
    src = repo / "Sources"
    src.mkdir()
    (src / "Existing.swift").write_text("// existing\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "base")
    # Branch off so base...HEAD is a real diff.
    _git(repo, "checkout", "-q", "-b", "feature")
    return repo


def _run_gate(repo, base="main"):
    return subprocess.run(
        ["bash", str(SCRIPT), base],
        cwd=repo, capture_output=True, text=True,
    )


def test_gate_blocks_source_change_without_changelog(tmp_path):
    repo = _init_repo(tmp_path, CHANGELOG_EMPTY)
    (repo / "Sources" / "Feature.swift").write_text("// new behavior\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "add feature, no changelog")
    result = _run_gate(repo)
    assert result.returncode != 0, (
        f"gate should FAIL for source change with empty [Unreleased]\n"
        f"stdout={result.stdout}\nstderr={result.stderr}"
    )
    assert "Unreleased" in (result.stdout + result.stderr)


def test_gate_passes_source_change_with_changelog(tmp_path):
    repo = _init_repo(tmp_path, CHANGELOG_EMPTY)
    (repo / "Sources" / "Feature.swift").write_text("// new behavior\n")
    (repo / "CHANGELOG.md").write_text(CHANGELOG_WITH_ENTRY)
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "add feature + changelog")
    result = _run_gate(repo)
    assert result.returncode == 0, (
        f"gate should PASS when [Unreleased] has an entry\n"
        f"stdout={result.stdout}\nstderr={result.stderr}"
    )


def test_gate_passes_docs_only_change(tmp_path):
    repo = _init_repo(tmp_path, CHANGELOG_EMPTY)
    (repo / "README.md").write_text("docs only\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "docs only, no changelog needed")
    result = _run_gate(repo)
    assert result.returncode == 0, (
        f"gate should PASS for a docs-only change with empty [Unreleased]\n"
        f"stdout={result.stdout}\nstderr={result.stderr}"
    )


def test_gate_ignores_generated_buildinfo(tmp_path):
    repo = _init_repo(tmp_path, CHANGELOG_EMPTY)
    (repo / "Sources" / "BuildInfo.swift").write_text("// generated stamp\n")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "regenerate build info")
    result = _run_gate(repo)
    assert result.returncode == 0, (
        f"gate should PASS when only the generated BuildInfo.swift changed\n"
        f"stdout={result.stdout}\nstderr={result.stderr}"
    )
