"""The latest release of a project on GitHub: the one outside call the control
plane makes. Fixed URLs only, nothing about the mini is sent, and a failure is
simply "unknown". Under TEST_MODE the answer comes from the HTTP fixtures.
"""

from __future__ import annotations

import json
import urllib.request
from typing import Optional

from homelab.adapters import http as hhttp
from homelab.exec import test_mode

REPOS = {"immich": "immich-app/immich"}


def latest(project: str, timeout: float = 8) -> Optional[str]:
    """The latest release tag, e.g. v2.3.1, or None if GitHub can't say."""
    repo = REPOS[project]
    url = f"https://api.github.com/repos/{repo}/releases/latest"
    if test_mode():
        fake = f"http://localhost:1/github/{repo}/releases/latest"
        r = hhttp.get(fake)
        return r.json().get("tag_name") if r.ok else None
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "homelab-updates-check",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310
            return json.loads(resp.read(1_000_000)).get("tag_name")
    except Exception:  # offline, rate-limited, anything: unknown, not an error
        return None
