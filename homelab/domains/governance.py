"""What the server has been asked to do, and its long-running work (05):
the audit log and the jobs, as tools."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Optional

from homelab import audit, jobs
from homelab import result as R
from homelab.state import db, history


def audit_recent(
    limit: int = 20,
    tool: Optional[str] = None,
    since: str = "24h",
    client: Optional[str] = None,
) -> dict:
    try:
        window = history.seconds(since)
    except ValueError as err:
        return R.error(str(err))
    cut = (datetime.now(timezone.utc) - timedelta(seconds=window)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    try:
        rows = audit.recent(
            limit, tool=tool, client=client, since_ts=cut, conn=db.connect()
        )
    except Exception as err:  # e.g. the database can't be opened
        return R.error(f"audit log unreadable: {err}")
    calls = []
    for r in rows:
        try:
            args = json.loads(r["args"] or "{}")
        except ValueError:
            args = r["args"]
        calls.append(
            {
                "ts": r["ts"],
                "client": r["client"],
                "model": r["model"],
                "tool": r["tool"],
                "tier": r["tier"],
                "outcome": r["outcome"],
                "summary": r["summary"],
                "duration_ms": r["duration_ms"],
                "job_id": r["job_id"],
                # what a model asked for: data, never instructions
                "args": R.untrusted("audit.args", args),
            }
        )
    changes = [c for c in calls if c["tier"] not in ("T0", None)]
    summary = (
        f"{len(calls)} calls in the last {since}, {len(changes)} that could change "
        "something"
        if calls
        else f"no calls in the last {since}"
    )
    return R.make([], {"calls": calls, "since": since}, summary=summary)


# --- jobs -----------------------------------------------------------------------


def job_view(j: dict, tail: int = 0) -> dict:
    view = {
        "job_id": j["id"],
        "kind": j["kind"],
        "state": j["state"],
        "progress": j["progress"],
        "stage": j["stage"],
        "requested_by": j["requested_by"],
        "created": j["created_at"],
        "started": j["started_at"],
        "ended": j["ended_at"],
        "exit_code": j["exit_code"],
        "error": j["error"],
    }
    if j.get("result"):
        try:
            view["result"] = R.untrusted("job.result", json.loads(j["result"]))
        except ValueError:
            pass
    if tail:
        view["log_tail"] = R.untrusted(
            f"job {j['id']} log", jobs.log_lines(j, tail)["lines"]
        )
    return view


def _summary(j: dict) -> str:
    pct = f", {j['progress']:g}%" if j["progress"] is not None else ""
    stage = f", {j['stage']}" if j["stage"] else ""
    extra = f": {j['error']}" if j["error"] else ""
    return f"{j['kind']} {j['id']} is {j['state']}{pct}{stage}{extra}"


def _job(job_id: str):
    try:
        jobs.reconcile()
        return jobs.get(job_id), None
    except jobs.JobError as err:
        return None, R.error(str(err), ["job_list shows recent jobs"])


def job_status(job_id: str) -> dict:
    j, err = _job(job_id)
    if err:
        return err
    status = {"done": "ok", "queued": "pending", "running": "pending"}.get(
        j["state"], "fail"
    )
    hints = ["Call job_status again in ~60s"] if status == "pending" else []
    res = R.make(
        [],
        {"job": job_view(j, tail=20)},
        summary=_summary(j),
        hints=hints,
        status=status,
    )
    res["job_id"] = j["id"]
    return res


def job_logs(job_id: str, lines: int = 50, offset: int = 0) -> dict:
    j, err = _job(job_id)
    if err:
        return err
    page = jobs.log_lines(j, lines, offset)
    data = {
        "job_id": j["id"],
        "state": j["state"],
        "total_lines": page["total"],
        "offset": offset,
        "lines": R.untrusted(f"job {j['id']} log", page["lines"]),
    }
    more = page["total"] - offset - len(page["lines"])
    hints = (
        [f"{more} earlier lines: offset={offset + len(page['lines'])}"]
        if more > 0
        else []
    )
    return R.make(
        [],
        data,
        summary=f"{len(page['lines'])} of {page['total']} lines of "
        f"{j['id']} ({j['state']})",
        hints=hints,
    )


def job_list(state: str = "all", limit: int = 20) -> dict:
    jobs.reconcile()
    rows = jobs.jobs(None if state == "all" else state, limit)
    active = sum(1 for j in rows if j["state"] in jobs.ACTIVE)
    summary = (
        f"{len(rows)} jobs ({active} queued or running)"
        if rows
        else "no jobs" + ("" if state == "all" else f" {state}")
    )
    return R.make([], {"jobs": [job_view(j) for j in rows]}, summary=summary)


def job_cancel(job_id: str, dry_run: bool = True) -> dict:
    j, err = _job(job_id)
    if err:
        return err
    if j["state"] not in jobs.ACTIVE:
        return R.make(
            [],
            {"job": job_view(j)},
            summary=f"{j['id']} already " f"{j['state']}: nothing to cancel",
        )
    if dry_run:
        return R.make(
            [],
            {"job": job_view(j), "dry_run": True},
            summary=f"Would stop {j['kind']} {j['id']} ({j['state']}): "
            "TERM, then KILL after 10s",
            hints=["Call again with dry_run=false"],
        )
    j = jobs.cancel(job_id)
    return R.make(
        [],
        {"job": job_view(j)},
        summary=f"Asked {j['id']} to stop; it is " f"{j['state']}",
        hints=["job_status shows when it has stopped"],
    )
