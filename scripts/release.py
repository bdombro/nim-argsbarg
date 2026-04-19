#!/usr/bin/env python3
"""Cut a new argsbarg release: SemVer bump, changelog promotion, checks, git tag, push, cache tidy.

This script orchestrates shipping a version of ``nim-argsbarg``. It sets the process working
directory to the repository root (the parent of ``scripts/``), regardless of where you invoke it
from.

**Steps (in order)**

1. **Preconditions** — If the working tree has uncommitted changes, run ``git add -A`` and
   ``git commit`` with a snapshot message so the release starts from a clean tip.

2. **SemVer bump** — Read ``argsbarg.nimble``, apply ``major`` / ``minor`` / ``patch`` to the
   current ``version = "X.Y.Z"`` line, and write the file.

3. **CHANGELOG** — Strip any existing GitHub reference-link footer, move everything under
   ``## [Unreleased]`` into a new ``## [new_version] - YYYY-MM-DD`` section, reset ``[Unreleased]``
   to empty, then append a fresh reference-link block: compare link for ``[Unreleased]`` against
   the newest released semver heading, and per-version release tag links.

4. **Quality gate** — Run ``just release-check`` (build, tests, shell syntax on generated
   completion scripts).

5. **Git publish** — ``git add`` the nimble and changelog files, commit ``Release vX.Y.Z.``,
   annotated tag ``vX.Y.Z``, push branch and tag to ``origin``.

6. **GitHub release** — ``gh release create`` for ``vX.Y.Z`` with the body taken from the matching
   ``## [X.Y.Z] - date`` section in ``CHANGELOG.md`` (subsections and bullets, without repeating the
   version heading). Requires the GitHub CLI (https://cli.github.com/) ``gh``, installed and
   authenticated (``gh auth login``).

7. **Local caches** — Best-effort removal of Nimble pkg/pkgcache globs for argsbarg and a few
   related app cache dirs so local tooling does not keep using stale installs.

**Usage:** ``python3 scripts/release.py major|minor|patch`` — exit non-zero on any failed step.
"""

from __future__ import annotations

import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import date
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
NIMBLE_NAME = "argsbarg.nimble"
CHANGELOG_NAME = "CHANGELOG.md"
GH = "https://github.com/bdombro/nim-argsbarg"


def ref_footer_for_changelog(changelog_text: str) -> str:
    """Builds the trailing ``[Unreleased]`` / ``[X.Y.Z]`` reference-link block."""
    vers = re.findall(r"^## \[(\d+\.\d+\.\d+)\]", changelog_text, re.M)
    lines = [f"[Unreleased]: {GH}/compare/v{vers[0]}...HEAD"]
    for v in vers:
        lines.append(f"[{v}]: {GH}/releases/tag/v{v}")
    return "\n" + "\n".join(lines) + "\n"


def strip_ref_footer(text: str) -> str:
    """Removes an existing GitHub reference-link footer from changelog text."""
    m = re.search(r"\n\[Unreleased\]: " + re.escape(GH) + r"/", text)
    if m:
        return text[: m.start()].rstrip() + "\n"
    return text


def bump_nimble_version(kind: str) -> str:
    """Writes the next SemVer into ``argsbarg.nimble`` and returns it."""
    path = REPO_ROOT / NIMBLE_NAME
    text = path.read_text()
    m = re.search(r'^version = "(\d+)\.(\d+)\.(\d+)"', text, re.M)
    if not m:
        raise SystemExit("error: could not parse version from argsbarg.nimble")
    major, minor, patch = map(int, m.groups())
    if kind == "major":
        new_ver = f"{major + 1}.0.0"
    elif kind == "minor":
        new_ver = f"{major}.{minor + 1}.0"
    elif kind == "patch":
        new_ver = f"{major}.{minor}.{patch + 1}"
    else:
        raise SystemExit(f"error: invalid bump kind {kind!r}")
    path.write_text(
        re.sub(
            r'^version = "\d+\.\d+\.\d+"',
            f'version = "{new_ver}"',
            text,
            count=1,
            flags=re.M,
        )
    )
    return new_ver


def changelog_release(new_ver: str) -> None:
    """Promotes ``[Unreleased]`` notes to ``## [new_ver] - date`` and rebuilds reference links."""
    path = REPO_ROOT / CHANGELOG_NAME
    text = strip_ref_footer(path.read_text())
    ur = re.search(r"^## \[Unreleased\]\s*\n", text, re.M)
    if not ur:
        raise SystemExit("error: CHANGELOG.md has no ## [Unreleased] section")
    start = ur.end()
    nxt = re.search(r"^## \[", text[start:], re.M)
    if not nxt:
        raise SystemExit("error: CHANGELOG.md: no release section after [Unreleased]")
    body = text[start : start + nxt.start()]
    rest = text[start + nxt.start() :]
    preamble = text[: ur.start()]
    today = date.today().isoformat()
    version_block = f"## [{new_ver}] - {today}\n"
    if body.strip():
        version_block += body
    else:
        version_block += "\n"
    merged = preamble + "## [Unreleased]\n\n" + version_block + rest
    merged = strip_ref_footer(merged).rstrip() + "\n"
    vers = re.findall(r"^## \[(\d+\.\d+\.\d+)\]", merged, re.M)
    if not vers:
        raise SystemExit("error: CHANGELOG.md has no ## [semver] section to anchor links")
    path.write_text(merged + ref_footer_for_changelog(merged))


def changelog_body_for_version(text: str, version: str) -> str:
    """Returns the markdown body under ``## [version]`` / ``## [version] - date`` (no heading line)."""
    esc = re.escape(version)
    until = r"(?=^## \[|^\[Unreleased\]: |\Z)"
    pat_dated = rf"(?ms)^## \[{esc}\] - \d{{4}}-\d{{2}}-\d{{2}}\s*\n(.*?){until}"
    m = re.search(pat_dated, text)
    if m:
        return m.group(1).strip()
    pat_bare = rf"(?ms)^## \[{esc}\]\s*\n(.*?){until}"
    m = re.search(pat_bare, text)
    if m:
        return m.group(1).strip()
    raise SystemExit(f"error: no CHANGELOG section found for version [{version}]")


def clear_caches() -> None:
    """Removes local Nimble and related caches so new installs are picked up."""
    home = str(Path.home())
    for pattern in (
        f"{home}/.nimble/pkgs2/argsbarg-*",
        f"{home}/.nimble/pkgcache/githubcom_bdombronimargsbarg*",
    ):
        for p in glob.glob(pattern):
            shutil.rmtree(p, ignore_errors=True)
    for rel in (".cache/gor", ".cache/nimr", ".cache/shebangsy"):
        d = Path(home) / rel
        if d.is_dir():
            shutil.rmtree(d, ignore_errors=True)


def git_commit_pending_if_any() -> None:
    """Stages and commits any pending changes so the release runs from a clean working tree."""
    r = subprocess.run(
        ["git", "status", "--porcelain"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if r.returncode != 0:
        raise SystemExit("error: git status failed")
    if not r.stdout.strip():
        return
    print(
        "Working tree has uncommitted changes; git add -A and committing snapshot.",
        file=sys.stderr,
    )
    subprocess.run(["git", "add", "-A"], cwd=REPO_ROOT, check=True)
    subprocess.run(
        ["git", "commit", "-m", "chore: snapshot before release"],
        cwd=REPO_ROOT,
        check=True,
    )


def publish_github_release(new_ver: str) -> None:
    """Creates a GitHub Release for ``v{new_ver}`` with notes from ``CHANGELOG.md``."""
    if not shutil.which("gh"):
        raise SystemExit(
            "error: GitHub CLI (gh) not found in PATH; install from https://cli.github.com/\n"
            "  and run: gh auth login"
        )
    text = (REPO_ROOT / CHANGELOG_NAME).read_text(encoding="utf-8")
    notes = changelog_body_for_version(text, new_ver)
    if not notes.strip():
        raise SystemExit(f"error: empty CHANGELOG body for version [{new_ver}]")
    with tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".md",
        delete=False,
        encoding="utf-8",
    ) as tmp:
        tmp.write(notes)
        tmp_path = tmp.name
    try:
        subprocess.run(
            [
                "gh",
                "release",
                "create",
                f"v{new_ver}",
                f"--title=v{new_ver}",
                "--notes-file",
                tmp_path,
            ],
            cwd=REPO_ROOT,
            check=True,
        )
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def run_git_tag_push(new_ver: str) -> None:
    """Commits nimble + changelog, tags, and pushes to origin."""
    msg = f"Release v{new_ver}."
    subprocess.run(
        ["git", "add", NIMBLE_NAME, CHANGELOG_NAME],
        cwd=REPO_ROOT,
        check=True,
    )
    subprocess.run(["git", "commit", "-m", msg], cwd=REPO_ROOT, check=True)
    subprocess.run(
        ["git", "tag", "-a", f"v{new_ver}", "-m", msg],
        cwd=REPO_ROOT,
        check=True,
    )
    subprocess.run(["git", "push", "origin", "HEAD"], cwd=REPO_ROOT, check=True)
    subprocess.run(
        ["git", "push", "origin", f"refs/tags/v{new_ver}"],
        cwd=REPO_ROOT,
        check=True,
    )


def run_release_check() -> None:
    """Runs ``just release-check`` from the repository root."""
    subprocess.run(["just", "release-check"], cwd=REPO_ROOT, check=True)


def main() -> None:
    """Entry point: parse ``argv`` and run the release pipeline."""
    if len(sys.argv) != 2:
        print("usage: release.py major|minor|patch", file=sys.stderr)
        raise SystemExit(2)
    kind = sys.argv[1]
    if kind not in ("major", "minor", "patch"):
        print("error: bump must be major, minor, or patch", file=sys.stderr)
        raise SystemExit(2)

    os.chdir(REPO_ROOT)
    git_commit_pending_if_any()
    new_ver = bump_nimble_version(kind)
    changelog_release(new_ver)
    run_release_check()
    run_git_tag_push(new_ver)
    publish_github_release(new_ver)
    print("Clearing local caches (to ensure local apps pick up the new version)")
    clear_caches()


if __name__ == "__main__":
    main()
