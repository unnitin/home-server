"""Media: what's waiting in staging, what failed, and what Plex and Jellyfin hold."""

from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from homelab import config
from homelab import result as R
from homelab.adapters import diskutil, jellyfin_api, plex_api
from homelab.adapters.service_api import optional

MAX_FILES = 100
STALE_HOURS = 24
VIDEO = {".mkv", ".mp4", ".m4v", ".avi", ".mov", ".ts", ".wmv", ".srt", ".sub"}


def _files(folder: Path, now: float) -> list[dict[str, Any]]:
    out = []
    try:
        paths = sorted(p for p in folder.rglob("*") if p.is_file())
    except OSError:
        return out
    for p in paths:
        if p.name.startswith("."):
            continue
        try:
            st = p.stat()
        except OSError:
            continue
        out.append(
            {
                "name": str(p.relative_to(folder)),
                "mb": round(st.st_size / 1_000_000, 1),
                "age_h": round((now - st.st_mtime) / 3600, 1),
            }
        )
    return out


def staging_list(library: str = "all", include_failed: bool = True) -> dict:
    m = config.load()
    libs = list(m.media.libraries) if library == "all" else [library]
    if any(lib not in m.media.libraries for lib in libs):
        return R.error(
            f"unknown library {library!r}; use all, {', '.join(m.media.libraries)}"
        )
    tier = m.storage.tiers[m.media.tier]
    if diskutil.volume(tier.mount) is None:
        return R.make(
            [
                R.check(
                    "media.tier",
                    "fail",
                    f"{m.media.tier} is not mounted: staging lives on it",
                    m.media.tier,
                )
            ],
            {"libraries": {}},
            hints=[f"storage_status(tier='{m.media.tier}')"],
        )
    root, now = Path(tier.mount), time.time()
    checks, data = [], {}
    for lib in libs:
        folder = root / m.media.staging / m.media.libraries[lib].staging
        files = _files(folder, now)
        stale = [f for f in files if f["age_h"] > STALE_HOURS]
        data[lib] = {
            "folder": str(folder),
            "waiting": len(files),
            "files": R.untrusted("file names", files[:MAX_FILES]),
        }
        if stale:
            checks.append(
                R.check(
                    f"media.staging.{lib}",
                    "warn",
                    f"{len(stale)} {lib} files waiting over {STALE_HOURS}h",
                    "media",
                )
            )
    result: dict[str, Any] = {"libraries": data}
    if include_failed:
        failed_root = root / m.media.failed
        failed = []
        if failed_root.is_dir():
            for day in sorted(failed_root.iterdir(), reverse=True):
                if day.is_dir():
                    failed += [dict(f, date=day.name) for f in _files(day, now)]
        result["failed"] = R.untrusted("file names", failed[:MAX_FILES])
        if failed:
            checks.append(
                R.check(
                    "media.failed",
                    "warn",
                    f"{len(failed)} files failed processing (in {m.media.failed})",
                    "media",
                )
            )
    waiting = sum(d["waiting"] for d in data.values())
    return R.make(
        checks,
        result,
        ok_summary=f"{waiting} files waiting in staging, none stuck",
        hints=["service_logs(service='media_watcher')"] if checks else [],
    )


def library_stats() -> dict:
    m = config.load()
    wanted = {
        str(Path(m.storage.tiers[m.media.tier].mount) / lib.dir)
        for lib in m.media.libraries.values()
    }
    checks: list[dict] = []
    hints: list[str] = []
    data: dict[str, Any] = {}

    plex, err = optional(lambda: plex_api.sections())
    if plex is None:
        checks.append(R.check("media.plex", "warn", err or "Plex unavailable", "plex"))
        if err and "secrets set" in err:
            hints.append(
                "homelab secrets import-plex (or: homelab secrets set plex_token)"
            )
    else:
        recent, _ = optional(lambda: plex_api.recently_added(5))
        data["plex"] = {
            "sections": [
                {
                    "title": s.title,
                    "type": s.type,
                    "items": s.items,
                    "scanned_at": s.scanned_at,
                    "refreshing": s.refreshing,
                    "paths": list(s.paths),
                }
                for s in plex
            ],
            "recently_added": R.untrusted(
                "plex",
                [
                    {"title": a.title, "year": a.year, "section": a.section}
                    for a in recent or []
                ],
            ),
        }
        stray = sorted({p for s in plex for p in s.paths} - wanted)
        if stray:
            checks.append(
                R.check(
                    "media.plex.paths",
                    "warn",
                    "Plex reads folders outside the manifest: " + ", ".join(stray),
                    "plex",
                )
            )

    jf_counts, err = optional(jellyfin_api.counts)
    if jf_counts is None:
        checks.append(
            R.check("media.jellyfin", "warn", err or "Jellyfin unavailable", "jellyfin")
        )
        if err and "secrets set" in err:
            hints.append("homelab secrets set jellyfin_api_key")
    else:
        libs, _ = optional(jellyfin_api.libraries)
        scan, _ = optional(jellyfin_api.last_scan)
        data["jellyfin"] = {
            "counts": jf_counts,
            "libraries": [
                {"name": lib.name, "type": lib.type, "paths": list(lib.paths)}
                for lib in libs or []
            ],
            "last_scan": scan and {"status": scan.status, "ended": scan.ended},
        }
        stray = sorted({p for lib in libs or [] for p in lib.paths} - wanted)
        if stray:
            checks.append(
                R.check(
                    "media.jellyfin.paths",
                    "warn",
                    "Jellyfin reads folders outside the manifest: " + ", ".join(stray),
                    "jellyfin",
                )
            )
        if scan and scan.status and scan.status != "Completed":
            checks.append(
                R.check(
                    "media.jellyfin.scan",
                    "warn",
                    f"Jellyfin's last library scan: {scan.status}",
                    "jellyfin",
                )
            )
    if diskutil.volume(m.storage.tiers[m.media.tier].mount) is None:
        checks.append(
            R.check(
                "media.tier",
                "warn",
                f"{m.media.tier} is not mounted: the servers list what they knew",
                "media",
            )
        )
    movies = next(
        (
            s["items"]
            for s in data.get("plex", {}).get("sections", [])
            if s["type"] == "movie"
        ),
        None,
    )
    return R.make(
        checks,
        data,
        ok_summary="Plex and Jellyfin libraries read"
        + (f": {movies} movies in Plex" if movies is not None else ""),
        hints=hints,
    )
