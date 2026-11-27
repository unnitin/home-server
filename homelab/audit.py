"""The audit log (docs/mcp-refactor/05, "Audit").

Every tools/call the MCP server answers is recorded: which token, the Tailscale
user and model if known, the tool and its tier, the arguments (redacted and
capped), the outcome, how long it took, and the job it started. Rows live in
the state database; each is also appended to <log_root>/mcp/audit.jsonl while
the log tier is mounted, for logs_search. Recording never fails a call.
"""

from __future__ import annotations

import json
import os
import sys
import time
from contextvars import ContextVar
from pathlib import Path
from typing import Any, Optional

from homelab import config, redact
from homelab.state import db

# Who is calling, for the jobs a call starts: the token's name over MCP, set by
# the server around each call (and carried into its worker thread), else cli.
CALLER: ContextVar[str] = ContextVar("homelab_caller", default="cli")
ARGS_MAX = 2000  # characters of JSON kept per row
SUMMARY_MAX = 200
_MOUNT_CACHE: dict[str, tuple[float, bool]] = {}
MOUNT_TTL = 60.0


def _log_tier_mounted(m: config.Manifest) -> Optional[Path]:
    """The log root, if the tier it's on is mounted (asked of diskutil, cached)."""
    log_root = Path(m.storage.log_root)
    for tier in m.storage.tiers.values():
        mount = Path(tier.mount)
        if log_root == mount or mount in log_root.parents:
            cached = _MOUNT_CACHE.get(tier.mount)
            if cached and time.monotonic() - cached[0] < MOUNT_TTL:
                return log_root if cached[1] else None
            from homelab.adapters import diskutil

            up = diskutil.volume(tier.mount) is not None
            _MOUNT_CACHE[tier.mount] = (time.monotonic(), up)
            return log_root if up else None
    return None


def mirror_path() -> Optional[Path]:
    override = os.environ.get("HOMELAB_AUDIT_JSONL")
    if override:
        return Path(override)
    if os.environ.get("TEST_MODE") == "1":
        return None
    root = _log_tier_mounted(config.load())
    return root / "mcp" / "audit.jsonl" if root else None


def clean_args(args: dict[str, Any]) -> str:
    text = json.dumps(redact.redact_obj(args), default=str, sort_keys=True)
    text = redact.redact(text)
    return text if len(text) <= ARGS_MAX else text[: ARGS_MAX - 1] + "…"


def record(
    *,
    client: str,
    tool: str,
    tier: Optional[str],
    args: dict[str, Any],
    outcome: str,
    summary: str = "",
    duration_ms: int = 0,
    tailscale_user: Optional[str] = None,
    model: Optional[str] = None,
    job_id: Optional[str] = None,
    plan_id: Optional[str] = None,
    conn=None,
) -> Optional[int]:
    row = {
        "ts": db.now(),
        "client": client,
        "tailscale_user": tailscale_user,
        "model": model,
        "tool": tool,
        "tier": tier,
        "args": clean_args(args),
        "outcome": outcome,
        "summary": redact.redact(summary or "")[:SUMMARY_MAX],
        "duration_ms": int(duration_ms),
        "job_id": job_id,
        "plan_id": plan_id,
    }
    rowid = None
    try:
        conn = conn or db.connect()
        cur = conn.execute(
            f"INSERT INTO audit ({', '.join(row)}) "
            f"VALUES ({', '.join('?' for _ in row)})",
            tuple(row.values()),
        )
        rowid = cur.lastrowid
    except Exception as err:  # the call has happened; losing its record is logged
        print(f"audit: could not record {tool}: {err}", file=sys.stderr)
    try:
        target = mirror_path()
        if target:
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open("a", encoding="utf-8") as fh:
                fh.write(json.dumps({"id": rowid, **row}) + "\n")
    except Exception as err:
        print(f"audit: could not append to the JSONL mirror: {err}", file=sys.stderr)
    return rowid


def recent(
    limit: int = 20,
    tool: Optional[str] = None,
    client: Optional[str] = None,
    since_ts: Optional[str] = None,
    conn=None,
) -> list[dict[str, Any]]:
    conn = conn or db.connect()
    where, params = [], []
    if tool:
        where.append("tool = ?")
        params.append(tool)
    if client:
        where.append("client = ?")
        params.append(client)
    if since_ts:
        where.append("ts >= ?")
        params.append(since_ts)
    sql = "SELECT * FROM audit"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY id DESC LIMIT ?"
    params.append(int(limit))
    return [dict(r) for r in conn.execute(sql, params).fetchall()]
