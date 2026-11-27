"""Incidents: one per failing component, opened and resolved by the snapshots.

- A component with a failing check and no open incident gets one. If its last
  incident closed less than an hour ago, that one is reopened instead, so a
  flapping disk makes one incident, not twenty.
- An incident the snapshots opened is resolved by the first snapshot in which
  nothing of its component fails.
- Incidents opened by hand (incident_open) are only closed by hand.
"""

from __future__ import annotations

import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from homelab.redact import redact
from homelab.state.db import now

REOPEN_WITHIN = timedelta(hours=1)


def _parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def event(
    conn: sqlite3.Connection,
    incident: int,
    kind: str,
    body: str,
    actor: str,
    ts: Optional[str] = None,
) -> None:
    conn.execute(
        "INSERT INTO incident_events (incident_id, ts, actor, kind, body) VALUES (?, "
        "?, ?, ?, ?)",
        (incident, ts or now(), actor, kind, redact(body)[:1000]),
    )


def open_(
    conn,
    component: str,
    severity: str,
    title: str,
    actor: str,
    key: Optional[str] = None,
    ts: Optional[str] = None,
) -> int:
    ts = ts or now()
    cur = conn.execute(
        "INSERT INTO incidents (key, opened_ts, component, severity, title, status) "
        "VALUES (?, ?, ?, ?, ?, 'open')",
        (key, ts, component, severity, redact(title)[:200]),
    )
    return int(cur.lastrowid)


def resolve(
    conn,
    incident: int,
    actor: str,
    root_cause: str = "",
    resolution: str = "",
    ts: Optional[str] = None,
) -> None:
    ts = ts or now()
    conn.execute(
        "UPDATE incidents SET status='resolved', closed_ts=?, "
        "root_cause=COALESCE(NULLIF(?, ''), root_cause), "
        "resolution=COALESCE(NULLIF(?, ''), resolution) WHERE id=?",
        (ts, redact(root_cause)[:1000], redact(resolution)[:1000], incident),
    )
    event(
        conn,
        incident,
        "action",
        f"resolved: {resolution or 'no longer failing'}",
        actor,
        ts,
    )


def reconcile(
    conn, failing: dict[str, list[dict[str, str]]], ts: str
) -> dict[str, list[int]]:
    """Open, reopen or resolve the snapshots' incidents. failing: component -> "
    "checks."""
    changes: dict[str, list[int]] = {"opened": [], "reopened": [], "resolved": []}
    open_rows = {
        r["key"]: r
        for r in conn.execute(
            "SELECT * FROM incidents WHERE status != 'resolved' AND key IS NOT NULL"
        )
    }
    for component, checks in sorted(failing.items()):
        key = f"auto:{component}"
        title = checks[0]["message"]
        detail = "; ".join(c["message"] for c in checks)
        if key in open_rows:
            continue
        last = conn.execute(
            "SELECT * FROM incidents WHERE key=? AND status='resolved' ORDER BY "
            "closed_ts DESC LIMIT 1",
            (key,),
        ).fetchone()
        if (
            last
            and last["closed_ts"]
            and _parse(ts) - _parse(last["closed_ts"]) < REOPEN_WITHIN
        ):
            conn.execute(
                "UPDATE incidents SET status='open', closed_ts=NULL WHERE id=?",
                (last["id"],),
            )
            event(
                conn,
                last["id"],
                "observation",
                f"failing again: {detail}",
                "snapshot",
                ts,
            )
            changes["reopened"].append(last["id"])
        else:
            iid = open_(conn, component, "fail", title, "snapshot", key=key, ts=ts)
            event(conn, iid, "observation", detail, "snapshot", ts)
            changes["opened"].append(iid)
    for key, row in open_rows.items():
        if not key.startswith("auto:"):
            continue
        if key[len("auto:") :] not in failing:
            resolve(conn, row["id"], "snapshot", ts=ts)
            changes["resolved"].append(row["id"])
    return changes


def listing(conn, status: str = "open", limit: int = 20) -> list[dict[str, Any]]:
    where = {
        "open": "status != 'resolved'",
        "resolved": "status = 'resolved'",
        "all": "1=1",
    }[status]
    rows = conn.execute(
        f"SELECT * FROM incidents WHERE {where} ORDER BY opened_ts DESC LIMIT ?",
        (limit,),
    ).fetchall()
    out = []
    for r in rows:
        events = conn.execute(
            "SELECT ts, actor, kind, body FROM incident_events WHERE incident_id=? "
            "ORDER BY rowid DESC LIMIT 5",
            (r["id"],),
        ).fetchall()
        out.append(
            {
                "id": r["id"],
                "component": r["component"],
                "severity": r["severity"],
                "title": r["title"],
                "status": r["status"],
                "opened": r["opened_ts"],
                "closed": r["closed_ts"],
                "auto": bool(r["key"]),
                "root_cause": r["root_cause"],
                "resolution": r["resolution"],
                "events": [dict(e) for e in events],
            }
        )
    return out
