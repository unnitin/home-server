#!/usr/bin/env python3
"""Docs must not send anyone to scripts that don't exist (Phase 1 doc hygiene).

- Every scripts/, diagnostics/, setup/ or tests/ path named in a Markdown file
  exists. The plan (docs/mcp-refactor/) and docs/FUTURE-EXTENSIONS.md name
  files still to be written, so they are left out.
- No script or diagnostic uses the retired /Volumes/Media or /Volumes/Photos.
- No doc uses the retired numbered script names (scripts/NN_*.sh).
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLANS = ("docs/mcp-refactor/", "docs/FUTURE-EXTENSIONS.md")
# Examples of a script you write yourself.
EXAMPLES = {"scripts/custom_maintenance.sh"}
PATH_RE = re.compile(
    r"(?<![\w/.-])(?:\./)?((?:scripts|diagnostics|setup|tests)/[A-Za-z0-9_./-]+"
    r"\.(?:sh|py|bats))"
)


def tracked(*patterns: str) -> list[str]:
    out = subprocess.run(
        ["git", "ls-files", *patterns], cwd=REPO, capture_output=True, text=True
    ).stdout
    return out.split()


def markdown_files() -> list[str]:
    return [f for f in tracked("*.md") if not f.startswith(PLANS)]


def test_every_script_path_in_the_docs_exists():
    missing = []
    for f in markdown_files():
        text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        for n, line in enumerate(text.splitlines(), 1):
            for path in PATH_RE.findall(line):
                if path not in EXAMPLES and not (REPO / path).exists():
                    missing.append(f"{f}:{n}: {path}")
    assert not missing, "docs name scripts that don't exist:\n" + "\n".join(missing)


def test_no_retired_volume_names_in_scripts():
    hits = []
    for f in tracked("scripts/*", "diagnostics/*"):
        text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        for n, line in enumerate(text.splitlines(), 1):
            if "/Volumes/Media" in line or "/Volumes/Photos" in line:
                hits.append(f"{f}:{n}")
    assert not hits, "retired volume names (use faststore/warmstore): " + str(hits)


def test_no_numbered_script_names_in_the_docs():
    numbered = re.compile(r"scripts/[0-9]{2}_\w+\.sh")
    hits = [
        f
        for f in markdown_files()
        if numbered.search((REPO / f).read_text(encoding="utf-8", errors="replace"))
    ]
    assert not hits, "retired scripts/NN_*.sh names in: " + ", ".join(hits)


def test_the_path_pattern_finds_paths():
    line = "Run ./scripts/core/health_check.sh, then diagnostics/run_all.sh."
    assert PATH_RE.findall(line) == [
        "scripts/core/health_check.sh",
        "diagnostics/run_all.sh",
    ]


def test_no_numbered_script_calls_in_code():
    """Scripts lost their NN_ prefixes; a call to an old name fails at run time."""
    numbered = re.compile(r"\b[0-9]{2}_[a-z_]+\.sh\b")
    hits = []
    code = tracked("scripts/*", "diagnostics/*", "launchd/*", "homelab_mcp/*")
    for f in code:
        if f == "setup/setup_flags.sh":  # deprecated; never touched
            continue
        text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        for n, line in enumerate(text.splitlines(), 1):
            if numbered.search(line):
                hits.append(f"{f}:{n}")
    assert not hits, "calls to retired scripts/NN_*.sh names: " + ", ".join(hits)


def test_no_retired_volume_names_in_the_docs():
    """faststore, warmstore and coldstore only (coldstore was Archive until 2026)."""
    retired = re.compile(r"/Volumes/(Media|Photos|Archive)\b")
    hits = []
    for f in markdown_files():
        if f == "docs/CLEANUP.md":  # the cleanup spec quotes the old names
            continue
        text = (REPO / f).read_text(encoding="utf-8", errors="replace")
        for n, line in enumerate(text.splitlines(), 1):
            if retired.search(line):
                hits.append(f"{f}:{n}")
    assert not hits, "retired volume names in the docs: " + ", ".join(hits)
