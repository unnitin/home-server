"""One snapshot: what the system looks like now, written to the state database.

Run every 15 minutes by io.homelab.snapshot (`python3 -m homelab snapshot`).
It records metrics for history_query, opens and resolves incidents, notes
version changes, prunes old rows, and once a day copies the database to the
archive tier when it's mounted. Memory is written by the system, so it doesn't
depend on any model remembering to (04).
"""

from __future__ import annotations

import json
import sqlite3
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

from homelab import config
from homelab import result as R
from homelab.adapters import diskutil, jellyfin_api, plex_api
from homelab.adapters.service_api import optional
from homelab.domains import network, photos, services, storage, system
from homelab.state import db, incidents

SNAPSHOT_FULL_DAYS = 14
METRICS_RAW_DAYS = 7
METRICS_KEEP_DAYS = 366
BACKUP_EVERY = timedelta(hours=24)
BACKUPS_KEPT = 14
UP = {"up": 1.0, "degraded": 0.5, "down": 0.0, "held": 0.0}


def gather() -> dict[str, dict]:
    """The domain results a snapshot is made of, in parallel."""
    jobs = {
        "storage": lambda: storage.status("all", True, True),
        "services": lambda: services.status("all", True),
        "tailscale": network.tailscale_status,
        "power": system.power_status,
        "photos": photos.stats,
    }
    with ThreadPoolExecutor(max_workers=len(jobs)) as pool:
        futures = {k: pool.submit(fn) for k, fn in jobs.items()}
        out = {}
        for k, f in futures.items():
            try:
                out[k] = f.result()
            except Exception as err:  # a snapshot never dies on one part
                out[k] = R.error(f"{k}: {type(err).__name__}: {err}")
    return out


def metrics_of(parts: dict[str, dict]) -> dict[str, float]:
    m: dict[str, float] = {}
    for name, t in (parts["storage"]["data"].get("tiers") or {}).items():
        m[f"storage.{name}.mounted"] = 1.0 if t["mounted"] else 0.0
        if t.get("usage"):
            m[f"storage.{name}.used_pct"] = float(t["usage"]["used_pct"])
            m[f"storage.{name}.free_gb"] = float(t["usage"]["free_gb"])
        if t.get("raid"):
            m[f"storage.{name}.raid_online"] = (
                1.0 if t["raid"]["status"] == "Online" else 0.0
            )
    for name, v in (parts["services"]["data"].get("services") or {}).items():
        if v["state"] in UP:
            m[f"svc.{name}.up"] = UP[v["state"]]
    ts = parts["tailscale"]["data"]
    if "connected" in ts:
        m["tailnet.connected"] = 1.0 if ts["connected"] else 0.0
        m["tailnet.mappings_ok"] = 1.0 if parts["tailscale"]["status"] == "ok" else 0.0
    lib = parts["photos"]["data"].get("library")
    if lib:
        m["immich.photos"] = float(lib["photos"])
        m["immich.videos"] = float(lib["videos"])
        m["immich.backlog"] = float(
            sum(
                q["backlog"]
                for q in (parts["photos"]["data"].get("queues") or {}).values()
            )
        )
    up = parts["power"]["data"].get("uptime_days")
    if up is not None:
        m["system.uptime_days"] = float(up)
    return m


def failing(parts: dict[str, dict]) -> dict[str, list[dict]]:
    """Component -> its failing checks. Warnings never open an incident."""
    out: dict[str, list[dict]] = {}
    for part in parts.values():
        for c in part["checks"]:
            if c["status"] == "fail":
                out.setdefault(c["component"], []).append(c)
    return out


def versions_of(parts: dict[str, dict]) -> dict[str, str]:
    v = {
        "macos": parts["power"]["data"].get("macos"),
        "tailscale": parts["tailscale"]["data"].get("version"),
        "immich": parts["photos"]["data"].get("version"),
        "plex": optional(plex_api.version)[0],
        "jellyfin": optional(jellyfin_api.version)[0],
    }
    return {k: val for k, val in v.items() if val}


def record_versions(
    conn: sqlite3.Connection, found: dict[str, str], ts: str
) -> list[str]:
    changed = []
    for component, version in found.items():
        row = conn.execute(
            "SELECT version FROM versions WHERE component=? ORDER BY ts DESC LIMIT 1",
            (component,),
        ).fetchone()
        if row is None or row["version"] != version:
            conn.execute(
                "INSERT INTO versions (component, version, ts, actor) VALUES (?, ?, "
                "?, 'snapshot')",
                (component, version, ts),
            )
            if row is not None:
                changed.append(f"{component} {row['version']} -> {version}")
    return changed


def _ago(days: int, now: datetime) -> str:
    return (now - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")


def prune(conn: sqlite3.Connection, now: Optional[datetime] = None) -> dict[str, int]:
    """Full snapshots for 14 days, then one a day; raw metrics for 7 days, then
    hourly averages for a year."""
    now = now or datetime.now(timezone.utc)
    cut = _ago(SNAPSHOT_FULL_DAYS, now)
    gone = conn.execute(
        "DELETE FROM snapshots WHERE ts < ? AND id NOT IN "
        "(SELECT MIN(id) FROM snapshots WHERE ts < ? GROUP BY substr(ts, 1, 10))",
        (cut, cut),
    ).rowcount
    raw = _ago(METRICS_RAW_DAYS, now)
    conn.execute("BEGIN")
    try:
        conn.execute(
            "CREATE TEMP TABLE IF NOT EXISTS hourly (ts TEXT, metric TEXT, value REAL)"
        )
        conn.execute("DELETE FROM hourly")
        conn.execute(
            "INSERT INTO hourly SELECT substr(ts, 1, 13) || ':00:00Z', metric, "
            "AVG(value) "
            "FROM metrics WHERE ts < ? GROUP BY metric, substr(ts, 1, 13)",
            (raw,),
        )
        squashed = conn.execute("DELETE FROM metrics WHERE ts < ?", (raw,)).rowcount
        conn.execute(
            "INSERT OR REPLACE INTO metrics SELECT ts, metric, value FROM hourly"
        )
        old = conn.execute(
            "DELETE FROM metrics WHERE ts < ?", (_ago(METRICS_KEEP_DAYS, now),)
        ).rowcount
        conn.execute("COMMIT")
    except sqlite3.Error:
        conn.execute("ROLLBACK")
        raise
    return {"snapshots": gone, "metrics_squashed": squashed, "metrics_dropped": old}


def backup(conn: sqlite3.Connection, now: Optional[datetime] = None) -> Optional[str]:
    """Copy the database to <archive>/homelab-backups once a day, when it's mounted."""
    now = now or datetime.now(timezone.utc)
    m = config.load()
    archive = m.storage.tiers.get("coldstore")
    if archive is None or diskutil.volume(archive.mount) is None:
        return None
    row = conn.execute(
        "SELECT value FROM inventory WHERE key='state_backup_ts'"
    ).fetchone()
    if (
        row
        and now
        - datetime.strptime(row["value"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
        < BACKUP_EVERY
    ):
        return None
    folder = Path(archive.mount) / "homelab-backups"
    folder.mkdir(exist_ok=True)
    dest = folder / f"state-{now.strftime('%Y%m%d')}.db"
    target = sqlite3.connect(str(dest))
    try:
        conn.backup(target)
    finally:
        target.close()
    for old in sorted(folder.glob("state-*.db"))[:-BACKUPS_KEPT]:
        old.unlink()
    stamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    conn.execute(
        "INSERT OR REPLACE INTO inventory (key, value, updated_ts) VALUES "
        "('state_backup_ts', ?, ?)",
        (stamp, stamp),
    )
    return str(dest)


def take(
    conn: Optional[sqlite3.Connection] = None, parts: Optional[dict] = None
) -> dict:
    started = time.monotonic()
    conn = conn or db.connect()
    parts = parts or gather()
    ts = db.now()
    overall = R.worst(p["status"] for p in parts.values())
    found = metrics_of(parts)
    found["snapshot.duration_s"] = round(time.monotonic() - started, 2)
    payload = {
        "overall": overall,
        "tiers": {
            n: {k: t.get(k) for k in ("mounted", "raid", "usage")}
            for n, t in (parts["storage"]["data"].get("tiers") or {}).items()
        },
        "services": {
            n: v["state"]
            for n, v in (parts["services"]["data"].get("services") or {}).items()
        },
        "problems": [
            {"id": c["id"], "status": c["status"], "message": c["message"]}
            for p in parts.values()
            for c in p["checks"]
            if c["status"] != "ok"
        ][:40],
    }
    conn.execute("BEGIN")
    try:
        conn.execute(
            "INSERT INTO snapshots (ts, overall, payload) VALUES (?, ?, ?)",
            (ts, overall, json.dumps(payload)),
        )
        conn.executemany(
            "INSERT OR REPLACE INTO metrics (ts, metric, value) VALUES (?, ?, ?)",
            [(ts, k, v) for k, v in found.items()],
        )
        changes = incidents.reconcile(conn, failing(parts), ts)
        changed = record_versions(conn, versions_of(parts), ts)
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    pruned = prune(conn)
    try:
        copied = backup(conn)
    except (OSError, sqlite3.Error) as err:  # the snapshot itself is already kept
        copied = f"failed: {err}"
    return {
        "ts": ts,
        "overall": overall,
        "metrics": len(found),
        "incidents": changes,
        "versions_changed": changed,
        "pruned": pruned,
        "backup": copied,
    }


def latest(conn: sqlite3.Connection) -> Optional[dict[str, Any]]:
    row = conn.execute(
        "SELECT ts, overall, payload FROM snapshots ORDER BY id DESC LIMIT 1"
    ).fetchone()
    if row is None:
        return None
    return {"ts": row["ts"], "overall": row["overall"], **json.loads(row["payload"])}
