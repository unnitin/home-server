#!/usr/bin/env python3
"""Tests for tests/e2e/vm/evaluate.py: how a rehearsal run is judged."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "evaluate", REPO / "tests/e2e/vm/evaluate.py"
)
assert spec and spec.loader
ev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ev)

BEFORE = {
    "jobs": {
        "io.homelab.storage": {"pid": None, "status": 126},
        "io.homelab.mcp": {"pid": 10, "status": 0},
    }
}
AFTER = {
    "jobs": {
        "io.homelab.storage": {"pid": None, "status": 0},
        "io.homelab.mcp": {"pid": 11, "status": 0},
        "io.homelab.colima": {"pid": None, "status": 1},
    },
    "mcp_initialize_http": "200",
    "plex_identity_http": "200",
    "jellyfin_health": "Healthy",
    "plex_movies": 272,
    "plex_sections": ["Movies", "TV Shows"],
    "jellyfin_wizard_done": True,
    "jellyfin_version": "10.11.2",
    "jellyfin_series": 14,
    "immich_database_mode": "700",
}


def make_run(tmp_path: Path, before=BEFORE, after=AFTER, guard="RESULT: OK") -> Path:
    for phase, data in (("1-documents", before), ("2-after-reboot", after)):
        d = tmp_path / "vm" / phase
        d.mkdir(parents=True)
        (d / "summary.json").write_text(json.dumps(data))
    (tmp_path / "vm-guard.txt").write_text(guard)
    (tmp_path / "host-guard.txt").write_text("RESULT: OK")
    return tmp_path


def failed(checks):
    return [c["check"] for c in checks if c["required"] and not c["ok"]]


def test_good_run_passes_with_colima_expected_to_fail(tmp_path):
    checks, passed = ev.evaluate(make_run(tmp_path))
    assert passed, failed(checks)
    colima = next(c for c in checks if c["check"] == "io.homelab.colima")
    assert colima["ok"] is None and not colima["required"]


def test_job_still_blocked_after_reboot_fails(tmp_path):
    after = copy.deepcopy(AFTER)
    after["jobs"]["io.homelab.storage"]["status"] = 126
    checks, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert not passed
    assert "io.homelab.storage" in failed(checks)


def test_mcp_down_fails(tmp_path):
    after = dict(AFTER, mcp_initialize_http="000")
    _, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert not passed


def test_database_folder_chmod_fails(tmp_path):
    after = dict(AFTER, immich_database_mode="755")
    checks, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert not passed
    assert "Immich database folder still 0700" in failed(checks)


def test_vm_guard_failure_fails(tmp_path):
    _, passed = ev.evaluate(
        make_run(tmp_path, guard="RESULT: FAIL - unexpected changes")
    )
    assert not passed


def test_restore_not_working_fails(tmp_path):
    after = dict(AFTER, plex_movies=0)
    checks, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert not passed
    assert "Plex backup restored" in failed(checks)


def test_missing_reports_fail(tmp_path):
    _, passed = ev.evaluate(tmp_path)
    assert not passed


def test_known_issue_is_shown_not_judged(tmp_path):
    after = copy.deepcopy(AFTER)
    after["jobs"]["io.homelab.media.watcher"] = {"pid": None, "status": 1}
    checks, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert passed, failed(checks)
    watcher = next(c for c in checks if c["check"] == "io.homelab.media.watcher")
    assert watcher["ok"] is None and "D21" in watcher["detail"]


def test_known_issue_job_blocked_by_d19_still_fails(tmp_path):
    after = copy.deepcopy(AFTER)
    after["jobs"]["io.homelab.media.watcher"] = {"pid": None, "status": 126}
    checks, passed = ev.evaluate(make_run(tmp_path, after=after))
    assert not passed
    assert "io.homelab.media.watcher" in failed(checks)


def test_d19_not_reproduced_is_info_only(tmp_path):
    before = {"jobs": {"io.homelab.mcp": {"pid": 1, "status": 0}}}
    checks, passed = ev.evaluate(make_run(tmp_path, before=before))
    assert passed
    d19 = checks[0]
    assert d19["ok"] is False and not d19["required"]
