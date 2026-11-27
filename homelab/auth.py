"""Bearer tokens for MCP clients (docs/mcp-refactor/05, "Bearer tokens").

`homelab token create NAME --scope ops` makes one and prints it once; only its
SHA-256 is kept in the state database. Every HTTP request must carry one
(`Authorization: Bearer …`), and what the token's scopes allow is decided by
config/policy.yaml. The Tailscale-User-Login header and X-Homelab-Model are
recorded with each call, never trusted: any local process could set them.

Over stdio (a person on the mini) the scope comes from HOMELAB_MCP_SCOPE,
default observe.
"""

from __future__ import annotations

import hashlib
import os
import re
import secrets
from dataclasses import dataclass, replace
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from homelab import policy
from homelab.state import db

PREFIX = "hlk_"
NAME = re.compile(r"^[a-z0-9][a-z0-9_.-]{0,63}$")
TOUCH_EVERY = timedelta(minutes=5)  # last_used_at is updated at most this often


class TokenError(ValueError):
    """A token request that can't be honoured (bad name, scope, toolset)."""


@dataclass(frozen=True)
class Client:
    """Who is calling: the token's name and what it may do."""

    name: str
    scopes: tuple[str, ...]
    toolset: Optional[str] = None
    tailscale_user: Optional[str] = None
    model: Optional[str] = None
    transport: str = "http"

    def with_request(
        self, tailscale_user: Optional[str], model: Optional[str]
    ) -> "Client":
        return replace(
            self,
            tailscale_user=(tailscale_user or None) and tailscale_user[:200],
            model=(model or None) and model[:100],
        )


def digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)


def _check_request(name: str, scopes: list[str], toolset: Optional[str]) -> None:
    pol = policy.load()
    if not NAME.match(name):
        raise TokenError(
            f"name {name!r}: lowercase letters, digits, '.', '_' or '-' (max 64)"
        )
    if not scopes:
        raise TokenError("give at least one scope: " + ", ".join(pol.scopes))
    unknown = [s for s in scopes if s not in pol.scopes]
    if unknown:
        raise TokenError(
            f"unknown scope {', '.join(unknown)}: choose from {', '.join(pol.scopes)}"
        )
    if toolset and toolset not in pol.toolsets:
        raise TokenError(
            f"unknown toolset {toolset!r}: choose from {', '.join(pol.toolsets)}"
        )


def create(
    name: str,
    scopes: list[str],
    toolset: Optional[str] = None,
    expires_days: Optional[int] = None,
    conn=None,
) -> str:
    """Make a token and return it. It can't be shown again."""
    _check_request(name, scopes, toolset)
    conn = conn or db.connect()
    if conn.execute("SELECT 1 FROM tokens WHERE name = ?", (name,)).fetchone():
        raise TokenError(f"a token named {name!r} exists: revoke it first")
    token = PREFIX + secrets.token_urlsafe(32)
    now = datetime.now(timezone.utc)
    expires = _iso(now + timedelta(days=expires_days)) if expires_days else None
    conn.execute(
        "INSERT INTO tokens (name, hash, scopes, toolset, created_at, expires_at) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        (name, digest(token), ",".join(scopes), toolset, _iso(now), expires),
    )
    return token


def verify(token: Optional[str], conn=None) -> Optional[Client]:
    """The client a token belongs to, or None (unknown, revoked or expired)."""
    if not token or not token.startswith(PREFIX) or len(token) > 200:
        return None
    conn = conn or db.connect()
    row = conn.execute(
        "SELECT * FROM tokens WHERE hash = ? AND revoked_at IS NULL", (digest(token),)
    ).fetchone()
    if row is None:
        return None
    now = datetime.now(timezone.utc)
    if row["expires_at"] and _parse(row["expires_at"]) <= now:
        return None
    last = row["last_used_at"]
    if not last or now - _parse(last) >= TOUCH_EVERY:
        conn.execute(
            "UPDATE tokens SET last_used_at = ? WHERE id = ?", (_iso(now), row["id"])
        )
    return Client(
        name=row["name"],
        scopes=tuple(s for s in row["scopes"].split(",") if s),
        toolset=row["toolset"],
    )


def revoke(name: str, conn=None) -> bool:
    conn = conn or db.connect()
    cur = conn.execute(
        "UPDATE tokens SET revoked_at = ? WHERE name = ? AND revoked_at IS NULL",
        (db.now(), name),
    )
    return cur.rowcount > 0


def tokens(conn=None) -> list[dict[str, Any]]:
    """Every token, never its value or hash."""
    conn = conn or db.connect()
    rows = conn.execute(
        "SELECT name, scopes, toolset, created_at, expires_at, last_used_at, "
        "revoked_at FROM tokens ORDER BY name"
    ).fetchall()
    return [dict(r) for r in rows]


def stdio_client() -> Client:
    """A person on the mini, over stdio: HOMELAB_MCP_SCOPE (default observe)."""
    raw = os.environ.get("HOMELAB_MCP_SCOPE", "observe")
    scopes = tuple(s.strip() for s in raw.split(",") if s.strip())
    known = policy.load().scopes
    return Client(
        name="stdio",
        scopes=tuple(s for s in scopes if s in known) or ("observe",),
        toolset=os.environ.get("HOMELAB_MCP_TOOLSET") or None,
        transport="stdio",
    )
