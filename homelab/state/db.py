"""Open the state database, and bring its schema up to date.

It lives on the internal disk (the manifest's storage.state_dir), never on a
RAID tier: the agent is needed most when those are gone. SQLite with WAL, so
the MCP server can read while the snapshot job writes. HOMELAB_STATE_DB points
it somewhere else (tests).
"""

from __future__ import annotations

import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from homelab import config

MIGRATIONS = Path(__file__).resolve().parent / "migrations"


def now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def path() -> Path:
    override = os.environ.get("HOMELAB_STATE_DB")
    if override:
        return Path(override)
    return config.expand(config.load().storage.state_dir) / "state.db"


def migrations() -> list[tuple[int, Path]]:
    out = []
    for f in sorted(MIGRATIONS.glob("*.sql")):
        out.append((int(f.name.split("_", 1)[0]), f))
    return out


def migrate(conn: sqlite3.Connection) -> int:
    """Apply every migration not yet applied; returns the schema version."""
    conn.execute(
        "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, ts "
        "TEXT)"
    )
    done = {row[0] for row in conn.execute("SELECT version FROM schema_version")}
    for version, file in migrations():
        if version in done:
            continue
        # One transaction per migration: it applies whole or not at all.
        script = (
            "BEGIN;\n"
            + file.read_text(encoding="utf-8")
            + f"\nINSERT INTO schema_version (version, ts) VALUES ({version}, "
            f"'{now()}');" + "\nCOMMIT;"
        )
        try:
            conn.executescript(script)
        except sqlite3.Error:
            if conn.in_transaction:
                conn.execute("ROLLBACK")
            raise
    row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
    return int(row[0] or 0)


def connect(db_path: Optional[Path] = None, create: bool = True) -> sqlite3.Connection:
    """A connection with the schema current. create=False: None-like error if "
    "missing."""
    target = db_path or path()
    if not create and not target.exists():
        raise FileNotFoundError(
            f"no state database at {target} (run: homelab snapshot)"
        )
    target.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(target), timeout=10, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA foreign_keys=ON")
    migrate(conn)
    return conn
