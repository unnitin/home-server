#!/usr/bin/env python3
"""Tests for the JSON mode of diagnostics/diag_lib.sh (DIAG_FORMAT=json).

Fixture scripts source the real library and run under /bin/bash (3.2, what
LaunchD uses). Set HOMELAB_LIVE_DIAG=1 to also run every real diagnostic on
this machine and validate its JSON stream; those only read system state.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
LIB = REPO / "diagnostics" / "diag_lib.sh"
BASH = "/bin/bash"
STATUSES = {"ok", "warn", "fail"}
SUMMARY_STATUSES = {"ok", "warn", "fail", "error", "unknown"}


def write_script(tmp_path: Path, name: str, body: str) -> Path:
    path = tmp_path / name
    path.write_text(
        "#!/usr/bin/env bash\nset -euo pipefail\n" f'source "{LIB}"\n{body}\n'
    )
    path.chmod(0o755)
    return path


def run(path: Path, fmt: str = "json", *args: str) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("DIAG_")}
    env["DIAG_FORMAT"] = fmt
    return subprocess.run(
        [BASH, str(path), *args], capture_output=True, text=True, env=env, timeout=60
    )


def records(stdout: str) -> list[dict]:
    return [json.loads(line) for line in stdout.splitlines()]


def assert_valid_stream(recs: list[dict]) -> None:
    """Every line is a known record, and the stream ends with a summary."""
    assert recs, "no JSON output"
    for r in recs:
        assert r["type"] in {"check", "info", "summary"}, r
        assert isinstance(r["component"], str) and r["component"], r
        if r["type"] == "check":
            assert r["status"] in STATUSES, r
            assert isinstance(r["id"], str) and isinstance(r["message"], str), r
        elif r["type"] == "summary":
            assert r["status"] in SUMMARY_STATUSES, r
            for k in ("passed", "warnings", "failures", "exit_code"):
                assert isinstance(r[k], int), r
            assert len(r["summary"]) < 200, r
    assert recs[-1]["type"] == "summary"


def test_stdout_carries_only_json_and_text_goes_to_stderr(tmp_path):
    s = write_script(
        tmp_path, "check_demo.sh", 'echo "plain"\nok "fine"\nprint_summary'
    )
    p = run(s)
    assert p.returncode == 0
    recs = records(p.stdout)
    assert_valid_stream(recs)
    assert "plain" in p.stderr and "plain" not in p.stdout


def test_awkward_text_survives_as_json(tmp_path):
    body = (
        "ok 'quote \" backslash \\\\ tab\tend'\n"
        "warn $'two\\nlines \\033[0;31mred\\033[0m & more'\n"
        'info "Plex 1.42 – ünïcødé ✅"\n'
        "print_summary"
    )
    recs = records(run(write_script(tmp_path, "check_demo.sh", body)).stdout)
    assert recs[0]["message"] == 'quote " backslash \\\\ tab\tend'  # two backslashes
    assert recs[1]["message"] == "two\nlines [0;31mred[0m & more"
    assert recs[2] == {
        "type": "info",
        "component": "demo",
        "section": "",
        "message": "Plex 1.42 – ünïcødé ✅",
    }


def test_component_and_ids_follow_the_catalog(tmp_path):
    body = 'section "HTTP & Ports"\nok a\nfail b\nprint_summary || true'
    recs = records(run(write_script(tmp_path, "check_plex_native.sh", body)).stdout)
    assert [r.get("id") for r in recs[:2]] == ["plex.http-ports.1", "plex.http-ports.2"]
    assert {r["component"] for r in recs} == {"plex"}
    assert recs[0]["section"] == "HTTP & Ports"


@pytest.mark.parametrize(
    "body, status, code",
    [
        ("ok a\nprint_summary", "ok", 0),
        ("ok a\nwarn b\nprint_summary", "warn", 0),
        ("ok a\nfail b\nprint_summary\nexit $?", "fail", 1),
        ("print_summary", "unknown", 0),
    ],
)
def test_summary_status_and_exit_code(tmp_path, body, status, code):
    p = run(write_script(tmp_path, "check_demo.sh", body))
    recs = records(p.stdout)
    assert_valid_stream(recs)
    assert (recs[-1]["status"], p.returncode) == (status, code)
    assert len([r for r in recs if r["type"] == "summary"]) == 1


def test_early_exit_still_ends_with_a_summary(tmp_path):
    p = run(write_script(tmp_path, "check_demo.sh", "ok a\nfalse\nok never"))
    recs = records(p.stdout)
    assert_valid_stream(recs)
    assert recs[-1]["status"] == "error" and recs[-1]["exit_code"] == 1
    assert [r["message"] for r in recs if r["type"] == "check"] == ["a"]


def test_child_diagnostics_share_the_parent_stream(tmp_path):
    child = write_script(
        tmp_path, "check_child.sh", 'echo noise\nok "child ok"\nprint_summary'
    )
    parent = write_script(
        tmp_path,
        "run_all.sh",
        f'echo "parent noise"\n"{child}" && diag_record ok child'
        " || diag_record fail child\nexit 0",
    )
    p = run(parent)
    recs = records(p.stdout)
    assert_valid_stream(recs)
    assert [(r["component"], r["type"]) for r in recs] == [
        ("child", "check"),
        ("child", "summary"),
        ("all", "check"),
        ("all", "summary"),
    ]
    assert "noise" in p.stderr


def test_text_mode_is_unchanged(tmp_path):
    p = run(write_script(tmp_path, "check_demo.sh", "ok fine\nprint_summary"), "text")
    assert "OK  - fine" in p.stdout and "Passed: 1" in p.stdout
    assert "{" not in p.stdout


def test_diag_record_counts_without_printing(tmp_path):
    body = "diag_record warn quiet\nprint_summary"
    p = run(write_script(tmp_path, "check_demo.sh", body), "text")
    assert "quiet" not in p.stdout.split("Warnings:")[0]
    assert "Warnings: 1" in p.stdout


def test_every_diagnostic_supports_json_mode():
    for script in sorted((REPO / "diagnostics").glob("*.sh")):
        if script.name == "diag_lib.sh":
            continue
        text = script.read_text()
        assert "diag_lib.sh" in text or "run_all.sh" in text, script.name


LIVE = os.environ.get("HOMELAB_LIVE_DIAG") == "1"
DIAGNOSTICS = sorted(
    p.name
    for p in (REPO / "diagnostics").glob("*.sh")
    if p.name not in {"diag_lib.sh", "collect_logs.sh"}  # collect_logs writes a bundle
)


@pytest.mark.skipif(not LIVE, reason="set HOMELAB_LIVE_DIAG=1 to run real diagnostics")
@pytest.mark.parametrize("name", DIAGNOSTICS)
def test_live_diagnostic_emits_valid_json(name):
    args = ["localhost", "2283"] if name == "network_port_check.sh" else []
    env = {k: v for k, v in os.environ.items() if not k.startswith("DIAG_")}
    env.update(DIAG_FORMAT="json", NO_COLOR="1")
    p = subprocess.run(
        [BASH, str(REPO / "diagnostics" / name), *args],
        capture_output=True,
        text=True,
        env=env,
        timeout=600,
    )
    assert_valid_stream(records(p.stdout))
