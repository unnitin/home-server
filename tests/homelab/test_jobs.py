"""The job runner (homelab/jobs.py): real supervisors running a test job."""

from __future__ import annotations

import inspect
import json
import subprocess
import sys
import time
from pathlib import Path

import pytest

from homelab import exec as hexec
from homelab import jobs, tools
from homelab.domains import governance
from homelab.state import db

REPO = Path(__file__).resolve().parents[2]
STEPS = str(REPO / "tests" / "fixtures" / "jobs" / "steps.sh")


@pytest.fixture(autouse=True)
def test_mode(monkeypatch):
    monkeypatch.setenv("TEST_MODE", "1")  # only the test jobs may run


def steps(code=0, secs=0.0, marker="/dev/null"):
    return ["bash", STEPS, str(code), str(secs), str(marker)]


def submit(argv, **kw):
    return jobs.submit("test", argv, timeout=kw.pop("timeout", 30), **kw)


def test_a_job_runs_to_done_with_progress_stage_and_result():
    job = submit(steps())
    assert job["state"] == "queued" and job["id"].startswith("j-")
    done = jobs.wait(job["id"])
    assert done["state"] == "done", done
    assert done["exit_code"] == 0 and done["progress"] == 100
    assert done["stage"] == "working"
    assert json.loads(done["result"]) == {"items": 3}
    assert "::progress 50" in Path(done["log_path"]).read_text()


def test_a_failing_job_is_failed_with_its_exit_code():
    done = jobs.wait(submit(steps(code=3))["id"])
    assert (done["state"], done["exit_code"], done["error"]) == ("failed", 3, "exit 3")


def test_a_job_past_its_timeout_is_stopped():
    done = jobs.wait(submit(steps(secs=30), timeout=1)["id"], timeout=30)
    assert done["state"] == "failed" and "timed out" in done["error"]


def test_cancel_stops_a_running_job():
    job = submit(steps(secs=30))
    for _ in range(50):
        if jobs.get(job["id"])["state"] == "running":
            break
        time.sleep(0.2)
    jobs.cancel(job["id"])
    done = jobs.wait(job["id"], timeout=20)
    assert done["state"] == "cancelled"


def _order(marker: Path) -> list[str]:
    return [line.split()[0] for line in marker.read_text().splitlines()]


def test_two_jobs_on_one_lock_run_one_after_the_other(tmp_path):
    marker = tmp_path / "ran.txt"
    first = submit(steps(secs=1.5, marker=marker), lock="media")
    second = submit(steps(secs=0, marker=marker), lock="media")
    time.sleep(1.0)
    assert jobs.get(second["id"])["state"] == "queued"
    assert jobs.wait(first["id"])["state"] == "done"
    assert jobs.wait(second["id"])["state"] == "done"
    assert _order(marker) == ["start", "end", "start", "end"]


def test_jobs_on_different_locks_overlap(tmp_path):
    marker = tmp_path / "ran.txt"
    a = submit(steps(secs=1.5, marker=marker), lock="a")
    b = submit(steps(secs=1.5, marker=marker), lock="b")
    assert jobs.wait(a["id"])["state"] == jobs.wait(b["id"])["state"] == "done"
    assert _order(marker) == ["start", "start", "end", "end"]


def test_at_most_max_running_jobs_run_at_once():
    many = [submit(steps(secs=2)) for _ in range(3)]
    time.sleep(1.5)
    states = sorted(jobs.get(j["id"])["state"] for j in many)
    assert states == ["queued", "running", "running"]
    for j in many:
        assert jobs.wait(j["id"])["state"] == "done"


def test_a_job_outlives_the_process_that_started_it(state_db):
    """What happens when LaunchD restarts the MCP server mid-job."""
    code = (
        "import json, sys; from homelab import jobs; "
        f"j = jobs.submit('test', {steps(secs=1)!r}, timeout=30); print(j['id'])"
    )
    out = subprocess.run(
        [sys.executable, "-c", code],
        cwd=REPO,
        capture_output=True,
        text=True,
        timeout=30,
        check=True,
    )
    job_id = out.stdout.strip()  # the submitting process has exited
    assert jobs.wait(job_id)["state"] == "done"


def test_a_job_whose_supervisor_is_gone_is_marked_lost():
    conn = db.connect()
    conn.execute(
        "INSERT INTO jobs (id, kind, argv, state, created_at, timeout_s, log_path, "
        "pid) VALUES ('j-20260101-000000-abcd', 'test', '[]', 'running', "
        "'2026-01-01T00:00:00Z', 60, '/dev/null', 999999)"
    )
    assert jobs.reconcile() == ["j-20260101-000000-abcd"]
    assert jobs.get("j-20260101-000000-abcd")["state"] == "lost"


def test_a_live_job_is_not_marked_lost():
    job = submit(steps(secs=2))
    time.sleep(1.0)
    assert jobs.reconcile() == []
    assert jobs.wait(job["id"])["state"] == "done"


@pytest.mark.parametrize(
    "argv",
    [
        ["bash", "-c", "echo hi"],
        ["bash", str(REPO / "scripts" / "storage" / "format_and_mount.sh")],
        ["diskutil", "eraseDisk", "APFS", "x", "disk9"],
        ["python", "-c", "print(1)"],
    ],
)
def test_jobs_only_run_allowed_programs(argv):
    with pytest.raises(hexec.ExecRefused):
        submit(argv)


def test_the_supervisor_checks_the_argv_again():
    """A row changed in the database can't get a command past the allowlist."""
    conn = db.connect()
    log = jobs.log_dir()
    log.mkdir(parents=True, exist_ok=True)
    conn.execute(
        "INSERT INTO jobs (id, kind, argv, state, created_at, timeout_s, log_path) "
        "VALUES ('j-20260101-000000-beef', 'test', ?, 'queued', ?, 60, ?)",
        (json.dumps(["bash", "-c", "touch /tmp/pwned"]), db.now(), str(log / "x.log")),
    )
    assert jobs.supervise("j-20260101-000000-beef") == 1
    job = jobs.get("j-20260101-000000-beef")
    assert job["state"] == "failed" and "refused" in job["error"]


def test_old_finished_jobs_are_pruned():
    done = jobs.wait(submit(steps())["id"])
    db.connect().execute(
        "UPDATE jobs SET created_at='2000-01-01T00:00:00Z' WHERE id=?", (done["id"],)
    )
    assert jobs.prune() == 1
    assert not Path(done["log_path"]).exists()


# --- the tools ------------------------------------------------------------------


def test_job_tools_report_state_logs_and_list():
    job = submit(steps())
    jobs.wait(job["id"])
    st = governance.job_status(job["id"])
    assert st["status"] == "ok" and st["job_id"] == job["id"]
    assert st["data"]["job"]["log_tail"]["type"] == "data"
    lg = governance.job_logs(job["id"], lines=2)
    assert len(lg["data"]["lines"]["content"]) == 2
    assert governance.job_list()["data"]["jobs"][0]["job_id"] == job["id"]
    assert governance.job_status("j-nope")["status"] == "error"


def test_job_cancel_is_a_dry_run_unless_asked():
    job = submit(steps(secs=5))
    dry = governance.job_cancel(job["id"])
    assert dry["data"]["dry_run"] is True and "Would stop" in dry["summary"]
    assert jobs.get(job["id"])["state"] in jobs.ACTIVE
    governance.job_cancel(job["id"], dry_run=False)
    assert jobs.wait(job["id"], timeout=20)["state"] == "cancelled"


def test_every_action_defaults_to_a_dry_run():
    for name, fn in tools.ACTIONS.items():
        param = inspect.signature(fn).parameters.get("dry_run")
        assert param is not None and param.default is True, name
