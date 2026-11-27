"""Long-running jobs (docs/mcp-refactor/05, "Long-running jobs").

A tool that would outlast a client's timeout (media processing, a log bundle,
an app restart) calls `submit`, which records the job and starts a supervisor,
`python3 -m homelab job-run <id>`, in its own session, then returns at once.
The supervisor:

1. holds `locks/job-<id>.lock` for as long as it lives: anyone can tell a live
   job from a lost one by trying that lock, whatever happened to the PID;
2. waits, as `queued`, for the job's lock (one `media` job at a time …) and for
   one of `jobs.max_running` slots (config/policy.yaml). Both are flock files,
   so a crashed supervisor releases them;
3. runs the argv through homelab.exec (checked again: the database isn't
   trusted), in its own process group, with a timeout;
4. writes its output to `jobs/<id>.log` and reads `::progress 42.5`,
   `::stage NAME` and `::result {json}` lines from it;
5. records done / failed / cancelled. SIGTERM (job_cancel) stops the job's
   process group: TERM, then KILL after a grace period.

Because the supervisor isn't the server's child in any way LaunchD tracks, a
server restart doesn't stop it. `reconcile` marks jobs whose supervisor is gone
`lost`.

Logs and locks live next to the state database, on the internal disk.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import secrets as _secrets
import signal
import subprocess
import sys
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

from homelab import exec as hexec
from homelab import policy, redact
from homelab.state import db

ACTIVE = ("queued", "running")
FINISHED = ("done", "failed", "cancelled", "lost")
STATES = ACTIVE + FINISHED
STARTING_GRACE = 60  # seconds a new job may take to show its supervisor
CANCEL_GRACE = 10  # seconds between TERM and KILL
KEEP_DAYS = 30
PROGRESS = re.compile(r"^::progress\s+(\d+(?:\.\d+)?)\s*$")
STAGE = re.compile(r"^::stage\s+(\S.{0,79})$")
RESULT = re.compile(r"^::result\s+(\{.*\})\s*$")


class JobError(Exception):
    """A job that can't be submitted, or found."""


def home() -> Path:
    """Where jobs keep their logs and locks: beside the state database."""
    return db.path().parent


def log_dir() -> Path:
    return home() / "jobs"


def lock_dir() -> Path:
    return home() / "locks"


def new_id(now: Optional[datetime] = None) -> str:
    now = now or datetime.now(timezone.utc)
    return f"j-{now:%Y%m%d-%H%M%S}-{_secrets.token_hex(2)}"


def _lock_file(name: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", name)
    folder = lock_dir()
    folder.mkdir(parents=True, exist_ok=True)
    return folder / f"{safe}.lock"


def try_lock(name: str):
    """An open, exclusively locked file, or None if someone holds it."""
    fh = open(_lock_file(name), "a+")
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        return None
    return fh


def held(name: str) -> bool:
    fh = try_lock(name)
    if fh is None:
        return True
    fh.close()
    return False


@contextmanager
def lock_now(name: str) -> Iterator[bool]:
    """For a quick action: the lock if it's free (True), else False at once."""
    fh = try_lock(name)
    try:
        yield fh is not None
    finally:
        if fh is not None:
            fh.close()


# --- submitting -------------------------------------------------------------------


def submit(
    kind: str,
    argv: list[str],
    *,
    tool: Optional[str] = None,
    args: Optional[dict[str, Any]] = None,
    lock: Optional[str] = None,
    timeout: int = 3600,
    requested_by: Optional[str] = None,
    conn=None,
) -> dict[str, Any]:
    """Record a job and start its supervisor. Returns the job's row."""
    hexec.check(argv)  # refuse now, not later in a log nobody reads
    conn = conn or db.connect()
    job_id = new_id()
    log = log_dir() / f"{job_id}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    conn.execute(
        "INSERT INTO jobs (id, kind, tool, args, argv, lock, state, requested_by, "
        "created_at, timeout_s, log_path) VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?, "
        "?, ?)",
        (
            job_id,
            kind,
            tool,
            json.dumps(redact.redact_obj(args or {}), default=str),
            json.dumps(list(argv)),
            lock,
            requested_by,
            db.now(),
            int(timeout),
            str(log),
        ),
    )
    try:
        hexec.spawn(supervisor_argv(job_id), log, env=_db_env())
    except Exception as err:
        _finish(conn, job_id, "failed", error=f"could not start: {err}")
        raise JobError(f"{kind}: the job could not start: {err}") from err
    return get(job_id, conn)


def supervisor_argv(job_id: str) -> list[str]:
    return ["python", "-m", "homelab", "job-run", job_id]


def _db_env() -> dict[str, str]:
    """The supervisor uses the same state database as its caller."""
    return {"HOMELAB_STATE_DB": str(db.path())}


# --- the supervisor ---------------------------------------------------------------


class _Cancelled(Exception):
    pass


def supervise(job_id: str) -> int:
    """Run one job to its end: `python3 -m homelab job-run <id>`."""
    conn = db.connect()
    row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
    if row is None:
        print(f"job-run: no job {job_id}", file=sys.stderr)
        return 2
    alive = try_lock(f"job-{job_id}")
    if alive is None:
        print(f"job-run: {job_id} already has a supervisor", file=sys.stderr)
        return 2
    cancel = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: cancel.set())
    signal.signal(signal.SIGINT, lambda *_: cancel.set())
    conn.execute("UPDATE jobs SET pid = ? WHERE id = ?", (os.getpid(), job_id))
    held_locks = []
    try:
        if row["state"] != "queued":
            print(f"job-run: {job_id} is {row['state']}", file=sys.stderr)
            return 2
        try:
            argv = json.loads(row["argv"])
            hexec.check(argv)
        except Exception as err:
            _finish(conn, job_id, "failed", error=f"refused: {err}")
            return 1
        try:
            held_locks = _wait_for_locks(row["lock"], cancel)
        except _Cancelled:
            _finish(conn, job_id, "cancelled", error="cancelled while queued")
            return 1
        conn.execute(
            "UPDATE jobs SET state = 'running', started_at = ? WHERE id = ?",
            (db.now(), job_id),
        )
        return _run(conn, job_id, argv, int(row["timeout_s"]), cancel)
    except Exception as err:  # the supervisor itself failed: say so
        _finish(conn, job_id, "failed", error=f"{type(err).__name__}: {err}")
        return 1
    finally:
        for fh in held_locks:
            fh.close()
        alive.close()


def _wait_for_locks(lock: Optional[str], cancel: threading.Event) -> list:
    """The job's own lock (if any), then a running slot. Polls, so a cancel
    while queued is seen within a second."""
    slots = policy.load().jobs.max_running
    mine = None
    while True:
        if cancel.is_set():
            if mine:
                mine.close()
            raise _Cancelled()
        if lock and mine is None:
            mine = try_lock(f"res-{lock}")
        if not lock or mine is not None:
            for n in range(slots):
                slot = try_lock(f"slot-{n}")
                if slot is not None:
                    return [h for h in (mine, slot) if h is not None]
        time.sleep(1)


def _run(conn, job_id: str, argv: list[str], timeout: int, cancel) -> int:
    proc = hexec.popen(argv)
    reader = threading.Thread(target=_read, args=(job_id, proc), daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    outcome, error = None, None
    while proc.poll() is None:
        if cancel.is_set():
            outcome, error = "cancelled", "cancelled"
            break
        if time.monotonic() > deadline:
            outcome, error = "failed", f"timed out after {timeout}s"
            break
        time.sleep(0.5)
    if outcome:
        _stop_group(proc)
    reader.join(timeout=10)
    rc = proc.wait()
    if outcome is None:
        outcome = "done" if rc == 0 else "failed"
        error = None if rc == 0 else f"exit {rc}"
    _finish(conn, job_id, outcome, exit_code=rc, error=error)
    return 0 if outcome == "done" else 1


def _stop_group(proc: subprocess.Popen) -> None:
    for sig, wait in ((signal.SIGTERM, CANCEL_GRACE), (signal.SIGKILL, 5)):
        try:
            os.killpg(proc.pid, sig)
        except (ProcessLookupError, PermissionError):
            return
        try:
            proc.wait(timeout=wait)
            return
        except subprocess.TimeoutExpired:
            continue


def _read(job_id: str, proc: subprocess.Popen) -> None:
    """Copy the job's output to its log (the supervisor's stdout) and pick up
    progress lines. Updates the row at most once a second, on its own
    connection (SQLite connections stay in their thread)."""
    conn = db.connect()
    last_write = 0.0
    pending: dict[str, Any] = {}
    assert proc.stdout is not None
    for raw in proc.stdout:
        line = hexec.clean_line(raw)
        print(line, flush=True)
        m = PROGRESS.match(line)
        if m:
            pending["progress"] = min(100.0, float(m.group(1)))
        m = STAGE.match(line)
        if m:
            pending["stage"] = m.group(1)
        m = RESULT.match(line)
        if m:
            try:
                pending["result"] = json.dumps(json.loads(m.group(1)))
            except ValueError:
                pass
        if pending and time.monotonic() - last_write >= 1:
            _try_update(conn, job_id, pending)
            pending, last_write = {}, time.monotonic()
    if pending:
        _try_update(conn, job_id, pending)


def _try_update(conn, job_id: str, fields: dict[str, Any]) -> None:
    try:  # progress is nice to have: never stop copying the output for it
        _update(conn, job_id, fields)
    except Exception as err:
        print(f"job-run: progress not recorded: {err}", file=sys.stderr, flush=True)


def _update(conn, job_id: str, fields: dict[str, Any]) -> None:
    sets = ", ".join(f"{k} = ?" for k in fields)
    conn.execute(f"UPDATE jobs SET {sets} WHERE id = ?", (*fields.values(), job_id))


def _finish(conn, job_id: str, state: str, exit_code=None, error=None) -> None:
    fields: dict[str, Any] = {"state": state, "ended_at": db.now()}
    if exit_code is not None:
        fields["exit_code"] = exit_code
    if error:
        fields["error"] = str(error)[:500]
    if state == "done":
        fields["progress"] = 100.0
    _update(conn, job_id, fields)


# --- looking ----------------------------------------------------------------------


def get(job_id: str, conn=None) -> dict[str, Any]:
    conn = conn or db.connect()
    row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
    if row is None:
        raise JobError(f"no job {job_id!r}")
    return dict(row)


def reconcile(conn=None) -> list[str]:
    """Mark jobs whose supervisor is gone as lost. Returns their ids."""
    conn = conn or db.connect()
    lost = []
    rows = conn.execute(
        f"SELECT id, pid, created_at FROM jobs WHERE state IN {ACTIVE}"
    ).fetchall()
    for row in rows:
        if held(f"job-{row['id']}"):
            continue  # its supervisor holds its lock: alive
        age = time.time() - _epoch(row["created_at"])
        if row["pid"] is None and age < STARTING_GRACE:
            continue  # still starting
        _finish(conn, row["id"], "lost", error="its supervisor is gone")
        lost.append(row["id"])
    return lost


def jobs(state: Optional[str] = None, limit: int = 20, conn=None) -> list[dict]:
    conn = conn or db.connect()
    if state:
        rows = conn.execute(
            "SELECT * FROM jobs WHERE state = ? ORDER BY created_at DESC LIMIT ?",
            (state, limit),
        )
    else:
        rows = conn.execute(
            "SELECT * FROM jobs ORDER BY created_at DESC LIMIT ?", (limit,)
        )
    return [dict(r) for r in rows.fetchall()]


def log_lines(job: dict[str, Any], lines: int = 50, offset: int = 0) -> dict:
    """The last `lines` lines of a job's log, skipping `offset` from the end."""
    path = Path(job["log_path"])
    if not path.exists():
        return {"lines": [], "total": 0}
    text = path.read_text(encoding="utf-8", errors="replace").splitlines()
    end = max(0, len(text) - offset)
    return {"lines": text[max(0, end - lines) : end], "total": len(text)}


def cancel(job_id: str, conn=None) -> dict[str, Any]:
    """Ask a job's supervisor to stop it. Returns the job as it is now."""
    conn = conn or db.connect()
    job = get(job_id, conn)
    deadline = time.monotonic() + 5
    while job["state"] in ACTIVE and not job["pid"] and time.monotonic() < deadline:
        time.sleep(0.1)  # its supervisor is starting: it records its PID once it
        job = get(job_id, conn)  # handles TERM
    if job["state"] not in ACTIVE:
        return job
    if job["pid"] and held(f"job-{job_id}"):
        try:
            os.kill(int(job["pid"]), signal.SIGTERM)
        except ProcessLookupError:
            pass
    else:
        reconcile(conn)
    return get(job_id, conn)


def wait(job_id: str, timeout: float = 30, conn=None) -> dict[str, Any]:
    """Block until a job finishes (tests, the CLI)."""
    conn = conn or db.connect()
    deadline = time.monotonic() + timeout
    while True:
        job = get(job_id, conn)
        if job["state"] in FINISHED or time.monotonic() > deadline:
            return job
        time.sleep(0.2)


def prune(conn=None, keep_days: int = KEEP_DAYS) -> int:
    """Forget finished jobs older than keep_days, and their logs."""
    conn = conn or db.connect()
    cut = (datetime.now(timezone.utc) - timedelta(days=keep_days)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    rows = conn.execute(
        f"SELECT id, log_path FROM jobs WHERE state IN {FINISHED} AND created_at < ?",
        (cut,),
    ).fetchall()
    for row in rows:
        try:
            Path(row["log_path"]).unlink()
        except OSError:
            pass
        conn.execute("DELETE FROM jobs WHERE id = ?", (row["id"],))
    return len(rows)


def _epoch(ts: str) -> float:
    return (
        datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )
