"""Service API secrets, kept in the login Keychain (service name `homelab`).

- `get(name)` reads one: HOMELAB_SECRET_<NAME> if set (tests, or a machine
  without a Keychain), else `security find-generic-password` through exec.py.
  Every value read is registered with redact.py, so it can't appear in a
  result even if a service echoes it back.
- `store(name, value)` is for the `homelab secrets` command only. No MCP tool
  writes a secret. The value goes to `security -i` on stdin, never in argv,
  so it doesn't show up in `ps`.

Names come from the manifest (`services.<name>.api.secret`).
"""

from __future__ import annotations

import os
import plistlib
import re
import subprocess
from pathlib import Path
from typing import Optional

from homelab import exec as hexec
from homelab import redact

SERVICE = "homelab"
SECURITY = "/usr/bin/security"
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
PLEX_PREFS = Path("~/Library/Preferences/com.plexapp.plexmediaserver.plist")

_cache: dict[str, Optional[str]] = {}


def _check(name: str) -> None:
    if not NAME.match(name):
        raise ValueError(f"secret names are lower_snake_case: {name!r}")


def env_name(name: str) -> str:
    return "HOMELAB_SECRET_" + name.upper()


def get(name: str) -> Optional[str]:
    """The secret, or None if it isn't set."""
    _check(name)
    from_env = os.environ.get(env_name(name))
    if from_env:
        redact.register(from_env)
        return from_env
    if name in _cache:
        return _cache[name]
    r = hexec.run(
        ["security", "find-generic-password", "-s", SERVICE, "-a", name, "-w"],
        timeout=10,
    )
    value = r.stdout.strip() if r.ok and r.stdout.strip() else None
    if value:
        redact.register(value)
    _cache[name] = value
    return value


def forget_cache() -> None:
    _cache.clear()


def store(name: str, value: str) -> None:
    """Add or replace a secret in the login Keychain. For the CLI only."""
    _check(name)
    if hexec.test_mode():
        raise RuntimeError("TEST_MODE: secrets are never written")
    if not value or any(c in value for c in '\n\r"\\'):
        raise ValueError("a secret is one line, without quotes or backslashes")
    command = f'add-generic-password -U -s {SERVICE} -a {name} -w "{value}"\n'
    proc = subprocess.run(
        [SECURITY, "-i"],
        input=command,
        capture_output=True,
        text=True,
        timeout=30,
    )
    if proc.returncode != 0 or "error" in (proc.stdout + proc.stderr).lower():
        raise RuntimeError(f"security could not store {name}")
    _cache.pop(name, None)


def plex_token_from_preferences() -> Optional[str]:
    """The token Plex Media Server keeps in its own preferences, if any.

    Used by `homelab secrets import-plex` only, when you choose to: it's the
    server's own sign-in token, so it never goes anywhere but the Keychain.
    """
    path = PLEX_PREFS.expanduser()
    try:
        data = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException, ValueError):
        return None
    token = data.get("PlexOnlineToken")
    return token if isinstance(token, str) and token else None
