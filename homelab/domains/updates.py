"""What could be updated: Homebrew, Immich (pinned vs latest), Plex, Jellyfin.

Only reports. Applying an update is a Phase 5 change that needs approval.
"""

from __future__ import annotations

import re
from typing import Any, Optional

from homelab import config
from homelab import result as R
from homelab.adapters import brew, docker, immich_api, jellyfin_api, plex_api
from homelab.adapters import releases
from homelab.adapters.service_api import optional

WATCHED = {
    "colima",
    "docker",
    "docker-compose",
    "tailscale",
    "plex-media-server",
    "jellyfin",
}


def _major(version: str) -> Optional[int]:
    m = re.match(r"v?(\d+)", version or "")
    return int(m.group(1)) if m else None


def _immich_tag(m: config.Manifest) -> Optional[str]:
    svc = m.services.get("immich")
    if not svc or not svc.compose_dir:
        return None
    project = docker.compose_ps(config.REPO / svc.compose_dir / "docker-compose.yml")
    for c in project.containers:
        if "immich-server" in c.image:
            return c.image.rsplit(":", 1)[-1] if ":" in c.image else "latest"
    return None


def check() -> dict:
    m = config.load()
    checks: list[dict] = []
    data: dict[str, Any] = {}

    outdated = brew.outdated()
    if outdated is None:
        checks.append(
            R.check("updates.brew", "warn", "brew outdated didn't answer", "homebrew")
        )
    else:
        watched = [o for o in outdated if o.name in WATCHED]
        data["homebrew"] = {
            "outdated": len(outdated),
            "watched": [
                {
                    "name": o.name,
                    "installed": o.installed,
                    "available": o.current,
                    "cask": o.cask,
                }
                for o in watched
            ],
        }
        if outdated:
            checks.append(
                R.check(
                    "updates.brew",
                    "warn",
                    f"{len(outdated)} Homebrew packages outdated"
                    + (
                        f", including {', '.join(o.name for o in watched)}"
                        if watched
                        else ""
                    ),
                    "homebrew",
                )
            )

    running, _ = optional(immich_api.version)
    tag = _immich_tag(m)
    latest = releases.latest("immich")
    data["immich"] = {"running": running, "image_tag": tag, "latest": latest}
    if tag in ("release", "latest"):
        checks.append(
            R.check(
                "updates.immich.pin",
                "warn",
                f"Immich runs the moving '{tag}' tag: a restart can pull a new version",
                "immich",
            )
        )
    if running and latest and latest.lstrip("v") != running.lstrip("v"):
        breaking = _major(latest) != _major(running)
        data["immich"]["major_change"] = breaking
        checks.append(
            R.check(
                "updates.immich",
                "warn",
                f"Immich {latest} is out (running {running})"
                + (
                    "; a major version: read the release notes first"
                    if breaking
                    else ""
                ),
                "immich",
            )
        )
    for name, fn in (("plex", plex_api.version), ("jellyfin", jellyfin_api.version)):
        data[name] = {"running": optional(fn)[0]}
    data["note"] = "Applying updates needs approval (Phase 5); this only reports."
    return R.make(
        checks,
        data,
        ok_summary="Everything is up to date"
        + (f" (Immich {running})" if running else ""),
    )
