"""Remove secrets from text before it leaves the control plane.

Every tool result passes through `redact` (docs/mcp-refactor/02): API keys,
Plex and Jellyfin tokens, bearer tokens, database passwords, Tailscale auth
keys and private keys. A secret the process has loaded (homelab/secrets.py)
is registered here and removed wherever it appears, whatever surrounds it.
"""

from __future__ import annotations

import re
from typing import Any

MASK = "[REDACTED]"
_KNOWN: set[str] = set()

_KEY = (
    r"(?:x-plex-token|plexonlinetoken|x-api-key|x-emby-token|x-mediabrowser-token"
    r"|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|token|secret"
    r"|[a-z_]*password|passwd)"
)
PATTERNS = [
    # -----BEGIN … PRIVATE KEY----- blocks
    (
        re.compile(
            r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
            re.S,
        ),
        MASK,
    ),
    # Authorization: Bearer xxx / Basic xxx
    (re.compile(r"(?i)\b(bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}"), r"\1 " + MASK),
    # MediaBrowser Token="xxx" (Jellyfin's auth header)
    (re.compile(r'(?i)(\btoken=")[^"]+(")'), r"\1" + MASK + r"\2"),
    # key=value, key: value, "key": "value", key="value" (query strings included)
    (
        re.compile(r"(?i)(\b" + _KEY + r"\b[\"']?\s*[:=]\s*[\"']?)([^\s\"'&,;}<]{4,})"),
        r"\1" + MASK,
    ),
    # Tailscale auth and API keys
    (re.compile(r"\btskey-[A-Za-z0-9-]{10,}"), MASK),
]


def register(secret: str) -> None:
    """Remove this exact value from every later result. Short values are ignored."""
    if secret and len(secret) >= 8:
        _KNOWN.add(secret)


def redact(text: str) -> str:
    for secret in sorted(_KNOWN, key=len, reverse=True):
        text = text.replace(secret, MASK)
    for pattern, repl in PATTERNS:
        text = pattern.sub(repl, text)
    return text


SECRET_KEY = re.compile(r"(?i)^" + _KEY + r"$")


def redact_obj(value: Any) -> Any:
    """`redact` applied to every string inside dicts, lists and tuples.

    A string under a key that names a secret (api_key, token, …) is masked whole.
    """
    if isinstance(value, str):
        return redact(value)
    if isinstance(value, dict):
        return {
            k: (
                MASK
                if isinstance(v, str) and v and SECRET_KEY.match(str(k))
                else redact_obj(v)
            )
            for k, v in value.items()
        }
    if isinstance(value, (list, tuple)):
        return type(value)(redact_obj(v) for v in value)
    return value
