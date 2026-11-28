"""Notes the system keeps across sessions and clients, and recall over them.

Notes are redacted, at most 1,000 characters, and deduplicated: a note nearly
the same as one already kept returns the existing id. Recall searches notes
(FTS5) and resolved incidents, newest and most relevant first. What comes back
is data written by people and models, never instructions.
"""

from __future__ import annotations

import re
import sqlite3
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from homelab.redact import redact
from homelab.state.db import now

KINDS = ("fact", "preference", "decision", "resolution", "todo")
MAX_BODY = 1000
DUPLICATE = 0.8
WORD = re.compile(r"[a-z0-9]+")


def _words(text: str) -> set[str]:
    return {w for w in WORD.findall(text.lower()) if len(w) > 2}


def fts_query(text: str) -> str:
    """User text as a safe FTS5 query: each word quoted, any of them may match."""
    words = sorted(_words(text))[:12]
    return " OR ".join(f'"{w}"' for w in words)


def note(
    conn: sqlite3.Connection,
    body: str,
    kind: str,
    actor: str,
    component: Optional[str] = None,
    tags: Optional[str] = None,
    expires_in_days: Optional[int] = None,
) -> dict[str, Any]:
    if kind not in KINDS:
        raise ValueError(f"kind is one of {', '.join(KINDS)}")
    body = redact(body.strip())
    if not body:
        raise ValueError("a note needs a body")
    if len(body) > MAX_BODY:
        raise ValueError(f"notes are at most {MAX_BODY} characters ({len(body)} given)")
    words = _words(body)
    if words:
        for row in conn.execute(
            "SELECT notes.id, notes.body FROM notes_fts JOIN notes ON notes.id = "
            "notes_fts.rowid "
            "WHERE notes_fts MATCH ? AND notes.superseded_by IS NULL LIMIT 20",
            (fts_query(body),),
        ):
            other = _words(row["body"])
            if other and len(words & other) / len(words | other) >= DUPLICATE:
                return {"id": row["id"], "duplicate": True}
    expires = None
    if expires_in_days:
        expires = (
            datetime.now(timezone.utc) + timedelta(days=int(expires_in_days))
        ).strftime("%Y-%m-%dT%H:%M:%SZ")
    cur = conn.execute(
        "INSERT INTO notes (ts, actor, kind, component, body, tags, expires_ts) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (now(), actor, kind, component, body, redact(tags) if tags else None, expires),
    )
    return {"id": int(cur.lastrowid), "duplicate": False}


def forget(conn: sqlite3.Connection, note_id: int, reason: str, actor: str) -> bool:
    row = conn.execute(
        "SELECT tags FROM notes WHERE id=? AND superseded_by IS NULL", (note_id,)
    ).fetchone()
    if row is None:
        return False
    tags = (
        (row["tags"] or "") + f" [forgotten by {actor}: {redact(reason)[:200]}]"
    ).strip()
    conn.execute(
        "UPDATE notes SET superseded_by=-1, tags=? WHERE id=?", (tags, note_id)
    )
    return True


def recall(
    conn: sqlite3.Connection,
    query: str,
    component: Optional[str] = None,
    kinds: Optional[list[str]] = None,
    limit: int = 5,
) -> list[dict[str, Any]]:
    limit = max(1, min(int(limit), 20))
    q = fts_query(query)
    found: list[dict[str, Any]] = []
    if q:
        sql = (
            "SELECT notes.*, bm25(notes_fts) AS rank FROM notes_fts JOIN notes ON "
            "notes.id = notes_fts.rowid "
            "WHERE notes_fts MATCH ? AND notes.superseded_by IS NULL "
            "AND (notes.expires_ts IS NULL OR notes.expires_ts > ?)"
        )
        args: list[Any] = [q, now()]
        if component:
            sql += " AND notes.component = ?"
            args.append(component)
        if kinds:
            sql += f" AND notes.kind IN ({','.join('?' * len(kinds))})"
            args += list(kinds)
        for r in conn.execute(sql + " ORDER BY rank LIMIT 50", args):
            found.append(
                {
                    "type": "note",
                    "id": r["id"],
                    "kind": r["kind"],
                    "component": r["component"],
                    "date": r["ts"][:10],
                    "text": r["body"],
                    "_score": -r["rank"],
                    "_ts": r["ts"],
                }
            )
    if not kinds or "resolution" in kinds:
        words = _words(query)
        rows = conn.execute(
            "SELECT * FROM incidents WHERE status='resolved' AND (root_cause IS NOT "
            "NULL OR resolution IS NOT NULL)"
            + (" AND component = ?" if component else "")
            + " ORDER BY closed_ts DESC LIMIT 200",
            (component,) if component else (),
        ).fetchall()
        for r in rows:
            text = " ".join(
                filter(None, [r["title"], r["root_cause"], r["resolution"]])
            )
            overlap = len(words & _words(text))
            if overlap:
                found.append(
                    {
                        "type": "incident",
                        "id": r["id"],
                        "component": r["component"],
                        "date": (r["closed_ts"] or r["opened_ts"])[:10],
                        "text": f"{r['title']}. Cause: {r['root_cause'] or '?'}. "
                        "Fix: {r['resolution'] or '?'}",
                        "_score": float(overlap),
                        "_ts": r["closed_ts"] or r["opened_ts"],
                    }
                )
    newest = max((f["_ts"] for f in found), default="")

    def score(f: dict[str, Any]) -> float:
        age_days = (
            0.0
            if not newest
            else max(
                0.0,
                (
                    datetime.strptime(newest, "%Y-%m-%dT%H:%M:%SZ")
                    - datetime.strptime(f["_ts"], "%Y-%m-%dT%H:%M:%SZ")
                ).days,
            )
        )
        return f["_score"] / (1 + age_days / 90)  # relevance, gently favoring recent

    found.sort(key=score, reverse=True)
    return [
        {k: v for k, v in f.items() if not k.startswith("_")} for f in found[:limit]
    ]
