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


# --- Phase 2 ---------------------------------------------------------------------

PHASE2 = {
    "snapshots_by_job": 2,
    "job_interval_900": True,
    "unmounted": True,
    "remounted": True,
    "mcp": {
        "instructions_words": 307,
        "tools": sorted(ev.PHASE2_TOOLS | {"check_raid"}),
        "calls": {
            "system_overview": {"is_error": False, "status": "warn", "bytes": 1500},
            "history_query": {"is_error": False, "status": "ok", "bytes": 900},
        },
        "resources": ["homelab://manifest", "homelab://topology"],
        "prompts": ["triage", "weekly_maintenance"],
    },
    "opened": [3],
    "resolved": [3],
    "incidents": [
        {"id": 1, "component": "warmstore", "status": "open", "title": "warmstore"},
        {"id": 3, "component": "faststore", "status": "resolved", "title": "fast"},
    ],
    "history_samples": 4,
}


def with_phase2(tmp_path: Path, p2: dict) -> Path:
    run = make_run(tmp_path)
    d = run / "vm" / "phase2"
    d.mkdir(parents=True)
    (d / "phase2.json").write_text(json.dumps(p2))
    return run


def test_phase2_good_run_passes(tmp_path):
    checks, passed = ev.evaluate(with_phase2(tmp_path, PHASE2))
    assert passed, failed(checks)
    names = {c["check"] for c in checks}
    assert {"Unmounting faststore opens an incident", "Remounting resolves it"} <= names


def test_phase2_without_its_output_is_not_judged(tmp_path):
    checks, passed = ev.evaluate(make_run(tmp_path))
    assert passed and not any("Snapshot job" in c["check"] for c in checks)


def test_phase2_an_incident_that_never_opens_fails(tmp_path):
    p2 = copy.deepcopy(PHASE2)
    p2["opened"] = []
    checks, passed = ev.evaluate(with_phase2(tmp_path, p2))
    assert not passed
    assert "Unmounting faststore opens an incident" in failed(checks)


def test_phase2_an_incident_left_open_fails(tmp_path):
    p2 = copy.deepcopy(PHASE2)
    p2["resolved"] = []
    checks, passed = ev.evaluate(with_phase2(tmp_path, p2))
    assert failed(checks) == ["Remounting resolves it"]


def test_phase2_missing_tools_or_a_tool_error_fails(tmp_path):
    p2 = copy.deepcopy(PHASE2)
    p2["mcp"]["tools"] = ["system_overview"]
    p2["mcp"]["calls"]["history_query"]["status"] = "error"
    checks, _ = ev.evaluate(with_phase2(tmp_path, p2))
    assert {
        "MCP serves the Phase 2 tools",
        "Phase 2 tools answer with envelopes",
    } <= set(failed(checks))


# --- Phase 3 ---------------------------------------------------------------------


def _job(state):
    return {"job": {"job": {"state": state, "result": {"content": {"bytes": 10}}}}}


PHASE3 = {
    "no_token_http": "401",
    "scopes": {
        "observe": {
            "tools": ["system_overview"],
            "t1_seen": [],
            "restart_default": {"is_error": True},
        },
        "ops": {
            "tools": ["system_overview"],
            "t1_seen": sorted(ev.T1_PROBED),
            "restart_default": {"is_error": False, "data": {"dry_run": True}},
        },
    },
    "jellyfin": {
        "pid_before": "100",
        "pid_after": "200",
        "health": "Healthy",
        **_job("done"),
    },
    "plex": {"identity_http": "200", **_job("done")},
    "sudoers": {
        "install_rc": 0,
        "check_rc": 0,
        "diskutil_allowed": False,
        "other_value_allowed": False,
    },
    "power": {
        "dry": {"data": {"drift": {"displaysleep": {}}}},
        "run": {"status": "ok"},
        "displaysleep_after": "1",
    },
    "bundle": _job("done"),
    "audit": {
        "observe": {
            "data": {"calls": [{"client": "rehearsal-observe", "outcome": "denied"}]}
        },
        "ops": {"data": {"calls": [{"client": "rehearsal-ops", "outcome": "ok"}]}},
    },
    "runs": {"plex": ["1", "1"], "jellyfin": ["1", "1"]},
}


def with_phase3(tmp_path: Path, p3: dict) -> Path:
    run = make_run(tmp_path)
    d = run / "vm" / "phase3"
    d.mkdir(parents=True)
    (d / "phase3.json").write_text(json.dumps(p3))
    return run


def test_phase3_good_run_passes(tmp_path):
    checks, passed = ev.evaluate(with_phase3(tmp_path, PHASE3))
    assert passed, failed(checks)
    assert "A job survives an MCP server restart" in {c["check"] for c in checks}


def test_phase3_a_restart_that_keeps_the_same_pid_fails(tmp_path):
    p3 = copy.deepcopy(PHASE3)
    p3["jellyfin"]["pid_after"] = "100"
    checks, _ = ev.evaluate(with_phase3(tmp_path, p3))
    assert failed(checks) == ["service_restart restarts Jellyfin"]


def test_phase3_a_lost_job_or_a_leaky_scope_fails(tmp_path):
    p3 = copy.deepcopy(PHASE3)
    p3["plex"]["job"]["job"]["state"] = "lost"
    p3["scopes"]["observe"]["t1_seen"] = ["service_restart"]
    p3["sudoers"]["diskutil_allowed"] = True
    checks, _ = ev.evaluate(with_phase3(tmp_path, p3))
    assert {
        "A job survives an MCP server restart",
        "An observe token sees no T1 tool and can't call one",
        "The sudo rule installs, and only its pmset commands skip the password",
    } <= set(failed(checks))


def test_phase3_a_job_that_keeps_relaunching_fails_d32(tmp_path):
    p3 = copy.deepcopy(PHASE3)
    p3["runs"]["plex"] = ["3", "5"]
    checks, _ = ev.evaluate(with_phase3(tmp_path, p3))
    assert failed(checks) == ["Plex and Jellyfin jobs stay in the foreground (D32)"]


def test_phase3_a_refusal_missing_from_the_audit_fails(tmp_path):
    p3 = copy.deepcopy(PHASE3)
    p3["audit"]["observe"]["data"]["calls"] = []
    checks, _ = ev.evaluate(with_phase3(tmp_path, p3))
    assert failed(checks) == ["Every call is audited, refused ones too"]
