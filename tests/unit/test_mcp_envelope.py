#!/usr/bin/env python3
"""Tests for the structured tools: homelab_mcp/envelope.py, health_check and
system_overview in mcp_routing.py, and their registration in mcp_server.py.

Diagnostics are faked at the subprocess boundary with DIAG_FORMAT=json output,
so nothing on the machine is read.
"""

from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "homelab_mcp"))

import envelope  # noqa: E402
import mcp_routing  # noqa: E402


def check(comp, status, message, n=1):
    return {
        "type": "check",
        "id": f"{comp}.main.{n}",
        "component": comp,
        "section": "",
        "status": status,
        "message": message,
    }


def summary(comp, status, passed=0, warnings=0, failures=0, exit_code=0):
    return {
        "type": "summary",
        "component": comp,
        "status": status,
        "summary": f"{comp}: …",
        "passed": passed,
        "warnings": warnings,
        "failures": failures,
        "exit_code": exit_code,
    }


HEALTHY = [check("immich", "ok", "HTTP 200"), summary("immich", "ok", passed=1)]


# --- envelope.py --------------------------------------------------------------


def test_parse_stream_counts_lines_that_are_not_records():
    text = json.dumps(HEALTHY[0]) + "\n\nnot json\n[1, 2]\n" + json.dumps(HEALTHY[1])
    records, bad = envelope.parse_stream(text)
    assert records == HEALTHY and bad == 2


def test_healthy_result_is_ok_with_no_checks_unless_verbose():
    env = envelope.build(HEALTHY)
    assert env["status"] == "ok"
    assert env["summary"] == "All 1 checks passed"
    assert env["checks"] == [] and env["hints"] == []
    assert envelope.build(HEALTHY, verbose=True)["checks"][0]["message"] == "HTTP 200"


def test_failure_outranks_warning_and_leads_the_summary():
    recs = [
        check("plex", "warn", "slow", 1),
        check("launchd", "fail", "io.homelab.plex exit 126", 2),
        summary("plex", "warn", 1, 1),
        summary("launchd", "fail", 0, 0, 1),
    ]
    env = envelope.build(recs)
    assert env["status"] == "fail"
    assert env["summary"] == "1 failing, 1 warnings: io.homelab.plex exit 126"
    assert [c["status"] for c in env["checks"]] == ["fail", "warn"]
    assert "health_check(component='launchd', verbose=true)" in env["hints"]


def test_summary_stays_under_200_characters():
    recs = [check("x", "fail", "word " * 100, i) for i in range(3)]
    env = envelope.build(recs + [summary("x", "fail", failures=3)])
    assert len(env["summary"]) < 200


def test_a_script_with_no_checks_proves_nothing():
    env = envelope.build([summary("raid", "unknown")])
    assert env["status"] == "warn"


def test_errors_make_an_error_unless_a_check_failed():
    assert envelope.build(HEALTHY, errors=["run_all.sh timed out"])["status"] == (
        "error"
    )
    failing = [check("x", "fail", "bad"), summary("x", "fail", failures=1)]
    assert envelope.build(failing, errors=["boom"])["status"] == "fail"
    assert envelope.build([])["status"] == "error"


def test_secrets_are_redacted():
    recs = [
        check("plex", "warn", "GET /library?X-Plex-Token=abc123def&x=1", 1),
        check("immich", "warn", "IMMICH_DB_PASSWORD=hunter2 in env", 2),
        check("mcp", "warn", "Authorization: Bearer eyJhbGciOi.xyz", 3),
        summary("plex", "warn", warnings=3),
    ]
    text = json.dumps(envelope.build(recs, errors=["x-api-key: k-123"]))
    for secret in ("abc123def", "hunter2", "eyJhbGciOi", "k-123"):
        assert secret not in text
    assert text.count("[redacted]") >= 4  # the error shows in summary and data


def test_results_are_capped_at_8_kb():
    recs = [check("x", "fail", f"failure {i} " + "z" * 200, i) for i in range(100)]
    env = envelope.build(recs + [summary("x", "fail", failures=100)])
    assert len(json.dumps(env, ensure_ascii=False).encode()) <= 8192
    assert env["truncated"] is True and 0 < len(env["checks"]) < 100


def test_render_text_is_compact():
    recs = [check("plex", "fail", "down"), summary("plex", "fail", failures=1)]
    text = envelope.render_text(envelope.build(recs))
    assert text.splitlines()[0] == "FAIL: 1 failing: down"
    assert "- [fail] plex: down" in text


# --- health_check and system_overview -----------------------------------------


@pytest.fixture
def fake_diagnostics(monkeypatch):
    """subprocess.run in mcp_routing returns canned JSON per script."""
    calls = []
    outputs = {}

    def fake_run(cmd, **kwargs):
        script = Path(cmd[1]).name
        calls.append((script, tuple(cmd[2:]), kwargs["env"].get("DIAG_FORMAT")))
        recs = outputs.get(script, HEALTHY)
        if recs == "timeout":
            raise subprocess.TimeoutExpired(cmd, kwargs["timeout"], output="")
        stdout = "\n".join(json.dumps(r) for r in recs)
        return subprocess.CompletedProcess(cmd, 0, stdout=stdout, stderr="noise")

    monkeypatch.setattr(mcp_routing.subprocess, "run", fake_run)
    return calls, outputs


def test_health_check_runs_its_component_scripts_in_json_mode(fake_diagnostics):
    calls, _ = fake_diagnostics
    env = mcp_routing.health_check("storage")
    assert sorted(c[0] for c in calls) == ["check_storage.sh", "verify_media_paths.sh"]
    assert {c[2] for c in calls} == {"json"}
    assert env["status"] == "ok" and env["data"]["component"] == "storage"


def test_network_checks_the_service_ports(fake_diagnostics):
    calls, _ = fake_diagnostics
    mcp_routing.health_check("network")
    assert sorted(c[1][1] for c in calls) == ["2283", "32400", "8096"]


def test_unknown_component_is_refused():
    with pytest.raises(ValueError, match="unknown component"):
        mcp_routing.health_check("nvme")


def test_a_timeout_is_reported_not_raised(fake_diagnostics):
    _, outputs = fake_diagnostics
    outputs["check_immich.sh"] = "timeout"
    env = mcp_routing.health_check("immich")
    assert env["status"] == "error"
    assert "timed out" in env["data"]["errors"][0]


def test_every_diagnostic_belongs_to_a_component():
    covered = {s for jobs in mcp_routing.COMPONENT_SCRIPTS.values() for s, _ in jobs}
    scripts = {p.name for p in (REPO / "diagnostics").glob("*.sh")}
    side_effects = {"diag_lib.sh", "collect_logs.sh", "full_summary.sh"}
    assert scripts - side_effects <= covered
    assert covered <= scripts


def test_tier_usage_needs_a_real_mount(tmp_path):
    (tmp_path / "warmstore").mkdir()  # an empty mount-point folder (D22)
    tiers = mcp_routing.tier_usage(str(tmp_path))
    assert tiers["warmstore"] == {"mounted": False, "used_pct": None}


def test_system_overview_on_a_healthy_box_is_under_2_kb(fake_diagnostics, monkeypatch):
    mounted = {"mounted": True, "used_pct": 41}
    monkeypatch.setattr(
        mcp_routing, "tier_usage", lambda: {t: dict(mounted) for t in mcp_routing.TIERS}
    )
    env = mcp_routing.system_overview()
    assert env["status"] == "ok"
    assert len(json.dumps(env).encode()) < 2048
    assert env["data"]["tiers"]["faststore"]["used_pct"] == 41


def test_system_overview_reports_an_unmounted_tier(fake_diagnostics, monkeypatch):
    tiers = {
        "faststore": {"mounted": True, "used_pct": 33},
        "warmstore": {"mounted": False, "used_pct": None},
        "coldstore": {"mounted": False, "used_pct": None},
    }
    monkeypatch.setattr(mcp_routing, "tier_usage", lambda: tiers)
    env = mcp_routing.system_overview()
    assert env["status"] == "fail"
    assert env["summary"].startswith("1 failing, 1 warnings: warmstore is not mounted")


def test_system_overview_caps_its_checks(fake_diagnostics, monkeypatch):
    _, outputs = fake_diagnostics
    many = [check("launchd", "fail", f"job {i} exit 126", i) for i in range(30)]
    outputs["check_launchd.sh"] = many + [summary("launchd", "fail", failures=30)]
    mounted = {"mounted": True, "used_pct": 41}
    monkeypatch.setattr(
        mcp_routing, "tier_usage", lambda: {t: dict(mounted) for t in mcp_routing.TIERS}
    )
    env = mcp_routing.system_overview()
    assert len(env["checks"]) == mcp_routing.OVERVIEW_MAX_CHECKS
    assert env["truncated"] is True


# --- registration in the MCP server -------------------------------------------


@pytest.fixture
def server():
    pytest.importorskip("mcp.server.fastmcp")
    import mcp_server

    return mcp_server


def test_structured_tools_publish_input_and_output_schemas(server):
    tools = {t.name: t for t in asyncio.run(server.build_server().list_tools())}
    hc = tools["health_check"]
    assert hc.inputSchema["properties"]["component"]["enum"] == mcp_routing.COMPONENTS
    for name in ("health_check", "system_overview"):
        props = tools[name].outputSchema["properties"]
        assert list(props) == [
            "status",
            "summary",
            "data",
            "checks",
            "hints",
            "truncated",
            "job_id",
        ]


def test_old_tools_say_what_replaces_them(server):
    tools = {t.name: t for t in asyncio.run(server.build_server().list_tools())}
    assert tools["check_immich"].description.startswith("Deprecated")
    assert "health_check(component='immich')" in tools["check_immich"].description
    assert not tools["check_port"].description.startswith("Deprecated")
    assert not tools["collect_logs"].description.startswith("Deprecated")


def test_health_check_returns_structured_content(server, fake_diagnostics):
    result = asyncio.run(
        server.build_server().call_tool("health_check", {"component": "power"})
    )
    content, structured = result if isinstance(result, tuple) else (result, None)
    assert structured is not None and structured["status"] == "ok"
    assert json.loads(content[0].text)["summary"] == "All 1 checks passed"


# --- the manifest, read without PyYAML ---------------------------------------


def test_read_manifest_env_unescapes_and_expands_home(tmp_path, monkeypatch):
    env = tmp_path / "homelab.env"
    env.write_text(
        "# comment\n"
        'HOMELAB_A="plain"\n'
        'HOMELAB_B="a \\"q\\" \\$x \\`c\\` \\\\ end"\n'
        'HOMELAB_C="$HOME/Library/x"\n'
        'NOT_OURS="skip"\n'
    )
    monkeypatch.setenv("HOME", str(tmp_path))
    values = mcp_routing.read_manifest_env(str(env))
    assert values == {
        "HOMELAB_A": "plain",
        "HOMELAB_B": 'a "q" $x `c` \\ end',
        "HOMELAB_C": str(tmp_path / "Library" / "x"),
    }


def test_read_manifest_env_missing_file_is_empty(tmp_path):
    assert mcp_routing.read_manifest_env(str(tmp_path / "none.env")) == {}


def test_tiers_come_from_the_manifest_with_coldstore_renamed():
    assert mcp_routing.TIERS == {
        "faststore": "faststore",
        "warmstore": "warmstore",
        "coldstore": "coldstore",  # was Archive until 2026-11-26 (D25)
    }


def test_network_checks_use_the_manifests_ports():
    ports = [args[1] for _, args in mcp_routing.COMPONENT_SCRIPTS["network"]]
    assert ports == ["2283", "32400", "8096"]
