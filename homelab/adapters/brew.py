"""Outdated Homebrew packages, from `brew outdated --json=v2`."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Optional

from homelab import exec as hexec


@dataclass(frozen=True)
class Outdated:
    name: str
    installed: str
    current: str
    cask: bool = False
    pinned: bool = False


def outdated() -> Optional[list[Outdated]]:
    """None when brew isn't installed or can't answer."""
    if not hexec.available("brew"):
        return None
    r = hexec.run(["brew", "outdated", "--json=v2"], timeout=120)
    if not r.ok:
        return None
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        return None
    out = []
    for kind in ("formulae", "casks"):
        for f in data.get(kind, []):
            installed = f.get("installed_versions") or [""]
            out.append(
                Outdated(
                    name=f.get("name", ""),
                    installed=installed[-1]
                    if isinstance(installed, list)
                    else installed,
                    current=f.get("current_version", ""),
                    cask=kind == "casks",
                    pinned=bool(f.get("pinned")),
                )
            )
    return out
