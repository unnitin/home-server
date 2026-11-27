"""What the server has been asked to do: the audit log as a tool (05)."""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Optional

from homelab import audit
from homelab import result as R
from homelab.state import db, history


def audit_recent(
    limit: int = 20, tool: Optional[str] = None, since: str = "24h"
) -> dict:
    try:
        window = history.seconds(since)
    except ValueError as err:
        return R.error(str(err))
    cut = (datetime.now(timezone.utc) - timedelta(seconds=window)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    try:
        rows = audit.recent(limit, tool=tool, since_ts=cut, conn=db.connect())
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
