"""History, incidents and memory as tools, over the state database.

Read tools say plainly when there's no history yet (the snapshot job hasn't
run). Write tools only ever add to the database (notes, incident events);
nothing here touches the system itself.
"""

from __future__ import annotations

from typing import Any, Optional

from homelab import result as R
from homelab.state import db, history, incidents, memory, snapshot


def _conn(create: bool = False):
    try:
        return db.connect(create=create), None
    except FileNotFoundError as err:
        return None, R.error(
            str(err), ["The snapshot job (io.homelab.snapshot) writes history"]
        )


def history_query(
    metric: str,
    since: str = "7d",
    bucket: str = "1h",
    above: Optional[float] = None,
    below: Optional[float] = None,
) -> dict:
    conn, err = _conn()
    if err:
        return err
    known = history.metrics(conn)
    if metric not in known:
        return R.error(
            f"no metric {metric!r}",
            data={"metrics": known},
            hints=["Pick one of data.metrics, e.g. storage.warmstore.used_pct"],
        )
    try:
        q = history.query(conn, metric, since, bucket, above, below)
    except ValueError as e:
        return R.error(str(e))
    if not q["samples"]:
        return R.make([], q, summary=f"{metric}: no samples in the last {since}")
    parts = [
        f"{metric} over {since}: {q['min']:g} to {q['max']:g}, now "
        f"{q['last']['value']:g}"
    ]
    for name in ("above", "below"):
        if name in q:
            t = q[name]
            when = t["last"]["ts"] if t["last"] else "never in this window"
            parts.append(f"last {name} {t['threshold']:g}: {when}")
    if q.get("trend_per_day") is not None:
        parts.append(f"trend {q['trend_per_day']:+g}/day")
    return R.make([], q, summary="; ".join(parts))


def incident_list(status: str = "open", limit: int = 20) -> dict:
    conn, err = _conn()
    if err:
        return err
    rows = incidents.listing(conn, status, max(1, min(int(limit), 50)))
    return R.make(
        [],
        {"incidents": R.untrusted("incidents", rows)},
        summary=f"{len(rows)} {status} incidents"
        + (": " + "; ".join(r["title"] for r in rows[:3]) if rows else ""),
    )


def incident_open(
    component: str, severity: str, title: str, actor: str = "mcp"
) -> dict:
    if severity not in ("fail", "warn"):
        return R.error("severity is fail or warn")
    conn, _ = _conn(create=True)
    iid = incidents.open_(conn, component, severity, title, actor)
    incidents.event(conn, iid, "note", f"opened by {actor}", actor)
    return R.make(
        [], {"incident_id": iid}, summary=f"incident {iid} opened: {title[:150]}"
    )


def incident_update(incident_id: int, kind: str, body: str, actor: str = "mcp") -> dict:
    if kind not in ("observation", "action", "hypothesis", "note"):
        return R.error("kind is observation, action, hypothesis or note")
    conn, err = _conn()
    if err:
        return err
    if (
        conn.execute("SELECT 1 FROM incidents WHERE id=?", (incident_id,)).fetchone()
        is None
    ):
        return R.error(f"no incident {incident_id}")
    incidents.event(conn, incident_id, kind, body, actor)
    return R.make(
        [],
        {"incident_id": incident_id},
        summary=f"incident {incident_id}: {kind} added",
    )


def incident_resolve(
    incident_id: int, root_cause: str, resolution: str, actor: str = "mcp"
) -> dict:
    conn, err = _conn()
    if err:
        return err
    row = conn.execute(
        "SELECT status FROM incidents WHERE id=?", (incident_id,)
    ).fetchone()
    if row is None:
        return R.error(f"no incident {incident_id}")
    if row["status"] == "resolved":
        conn.execute(
            "UPDATE incidents SET root_cause=?, resolution=? WHERE id=?",
            (root_cause[:1000], resolution[:1000], incident_id),
        )
        incidents.event(conn, incident_id, "note", "cause and fix recorded", actor)
    else:
        incidents.resolve(conn, incident_id, actor, root_cause, resolution)
    return R.make(
        [],
        {"incident_id": incident_id},
        summary=f"incident {incident_id} resolved; memory_recall will find its fix",
    )


def memory_recall(
    query: str,
    component: Optional[str] = None,
    kinds: Optional[list[str]] = None,
    limit: int = 5,
) -> dict:
    conn, err = _conn()
    if err:
        return err
    found = memory.recall(conn, query, component, kinds, limit)
    return R.make(
        [],
        {"query": query, "found": R.untrusted("memory", found)},
        summary=f"{len(found)} notes and past incidents for {query!r}",
    )


def memory_note(
    body: str,
    kind: str,
    component: Optional[str] = None,
    tags: Optional[str] = None,
    expires_in_days: Optional[int] = None,
    actor: str = "mcp",
) -> dict:
    conn, _ = _conn(create=True)
    try:
        out = memory.note(conn, body, kind, actor, component, tags, expires_in_days)
    except ValueError as e:
        return R.error(str(e))
    what = "already known as" if out["duplicate"] else "kept as"
    return R.make([], out, summary=f"note {what} {out['id']}")


def memory_forget(note_id: int, reason: str, actor: str = "mcp") -> dict:
    conn, err = _conn()
    if err:
        return err
    if not memory.forget(conn, note_id, reason, actor):
        return R.error(f"no current note {note_id}")
    return R.make(
        [], {"note_id": note_id}, summary=f"note {note_id} forgotten (kept, hidden)"
    )


def overview_extra() -> dict[str, Any]:
    """Open incidents and the last snapshot, for system_overview. {} without a DB."""
    try:
        conn = db.connect(create=False)
    except (FileNotFoundError, OSError):
        return {}
    rows = incidents.listing(conn, "open", 5)
    last = snapshot.latest(conn)
    return {
        "incidents": {"open": len(rows), "titles": [r["title"] for r in rows[:3]]},
        "last_snapshot": last["ts"] if last else None,
    }
