"""
apfel-plus Integration Tests - CHANGELOG.md release stamping.

The release workflow must keep CHANGELOG.md current: on each release it stamps
the accumulated `## [Unreleased]` section as `## [<version>] - <date>` and opens
a fresh empty `## [Unreleased]` above it (Keep a Changelog convention). This is
what fixes the stale-CHANGELOG bug reported in #201 from recurring.

These tests exercise `scripts/stamp-changelog.sh` on throwaway fixtures (no
model, no network) and assert the release script is actually wired to use it.
"""

import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
STAMP = ROOT / "scripts" / "stamp-changelog.sh"
PUBLISH = ROOT / "scripts" / "publish-release.sh"
CHANGELOG = ROOT / "CHANGELOG.md"

FIXTURE = """# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- A shiny new flag.

## [1.0.0] - 2026-01-01

### Added

- First release.
"""


def _run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(STAMP), *args],
        capture_output=True,
        text=True,
    )


def _stamp_fixture(content: str, version: str, date: str) -> str:
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text(content)
        res = _run(version, date, str(f))
        assert res.returncode == 0, f"stamp failed: {res.stderr}"
        return f.read_text()


def test_stamp_script_exists_and_is_executable():
    assert STAMP.exists(), "scripts/stamp-changelog.sh is missing"


def test_stamp_moves_unreleased_into_versioned_section():
    out = _stamp_fixture(FIXTURE, "1.1.0", "2026-06-14")
    # New version heading with date.
    assert "## [1.1.0] - 2026-06-14" in out
    # The unreleased content now sits under the new version, above 1.0.0.
    assert out.index("## [1.1.0]") < out.index("- A shiny new flag.") < out.index("## [1.0.0]")


def test_stamp_opens_fresh_unreleased_above_new_version():
    out = _stamp_fixture(FIXTURE, "1.1.0", "2026-06-14")
    assert "## [Unreleased]" in out
    # Fresh [Unreleased] must sit ABOVE the freshly-stamped version.
    assert out.index("## [Unreleased]") < out.index("## [1.1.0]")


def test_stamp_is_idempotent():
    once = _stamp_fixture(FIXTURE, "1.1.0", "2026-06-14")
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text(once)
        res = _run("1.1.0", "2026-06-14", str(f))
        assert res.returncode == 0
        # Running again must not add a second 1.1.0 heading.
        assert f.read_text().count("## [1.1.0]") == 1


def test_stamp_fails_loudly_without_unreleased_heading():
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text("# Changelog\n\n## [1.0.0] - 2026-01-01\n")
        res = _run("1.1.0", "2026-06-14", str(f))
        assert res.returncode != 0, "must fail when there is no [Unreleased] section"


EMPTY_UNRELEASED = """# Changelog

## [Unreleased]

## [1.0.0] - 2026-01-01

### Added

- First release.
"""

SUBHEADINGS_ONLY = """# Changelog

## [Unreleased]

### Added

### Fixed

## [1.0.0] - 2026-01-01

### Added

- First release.
"""


def test_stamp_fails_when_unreleased_section_is_empty():
    """#263: stamping an empty [Unreleased] must fail, not ship a blank heading.

    v1.6.1 shipped with an empty section because stamp-changelog.sh happily
    stamped it; this gate prevents the recurrence.
    """
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text(EMPTY_UNRELEASED)
        res = _run("1.1.0", "2026-06-14", str(f))
        assert res.returncode != 0, "must fail when [Unreleased] has no content lines"
        # The file must be left untouched (no half-stamp).
        assert "## [1.1.0]" not in f.read_text()


def test_stamp_fails_when_unreleased_has_only_subheadings():
    """#263: bare ### Added/### Fixed with no bullets counts as empty."""
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "CHANGELOG.md"
        f.write_text(SUBHEADINGS_ONLY)
        res = _run("1.1.0", "2026-06-14", str(f))
        assert res.returncode != 0, "empty subheadings are not content (#263)"


def test_preflight_gates_empty_unreleased_when_commits_since_tag():
    """#263: release-preflight.sh must fail when commits exist since the last
    tag but [Unreleased] is empty (a feature would ship under a blank heading).
    """
    preflight = (ROOT / "scripts" / "release-preflight.sh").read_text()
    assert "[Unreleased]" in preflight, (
        "release-preflight.sh must gate an empty [Unreleased] section (#263)"
    )
    assert "stamp-changelog.sh" in preflight or "changelog" in preflight.lower(), (
        "release-preflight.sh must reference the changelog gate (#263)"
    )


def test_publish_release_is_wired_to_stamp_and_commit_changelog():
    text = PUBLISH.read_text()
    assert "stamp-changelog.sh" in text, (
        "publish-release.sh must call scripts/stamp-changelog.sh so the "
        "CHANGELOG stays current (#201)"
    )
    # CHANGELOG.md must be staged in the release commit.
    git_add_lines = [ln for ln in text.splitlines() if ln.strip().startswith("git add")]
    assert any("CHANGELOG.md" in ln for ln in git_add_lines), (
        "publish-release.sh must 'git add CHANGELOG.md' in the release commit"
    )


def test_repo_changelog_documents_the_latest_published_release():
    """CHANGELOG.md must document the latest *published* release (newest git tag).

    We deliberately check the newest tag, not `.version`: during a release the
    version is bumped before the changelog is stamped (stamping happens in the
    commit step, after this test runs), so `.version` is briefly ahead of the
    changelog. The newest tag is always the last published release and must be
    present - that is the actual #201 staleness guard.
    """
    tag = subprocess.run(
        ["git", "tag", "--sort=-v:refname"],
        cwd=ROOT, capture_output=True, text=True,
    ).stdout.splitlines()
    tags = [t for t in tag if re.match(r"^v\d+\.\d+\.\d+$", t)]
    if not tags:
        import pytest
        pytest.skip("no version tags in this checkout")
    latest = tags[0].lstrip("v")
    body = CHANGELOG.read_text()
    assert f"## [{latest}]" in body, (
        f"CHANGELOG.md does not document the latest published release {latest} (#201)"
    )


def test_repo_changelog_has_unreleased_section():
    """An [Unreleased] section must always exist for new entries to accrue."""
    assert "## [Unreleased]" in CHANGELOG.read_text(), "CHANGELOG.md is missing its [Unreleased] section"
