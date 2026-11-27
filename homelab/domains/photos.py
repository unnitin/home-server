"""Photos: Immich's library totals, its background job queues, and its tier."""

from __future__ import annotations

from homelab import config
from homelab import result as R
from homelab.adapters import diskutil, immich_api
from homelab.adapters.service_api import ApiError, SecretMissing

GB = 1_000_000_000


def stats() -> dict:
    m = config.load()
    checks, hints = [], []
    data: dict = {}
    try:
        data["version"] = immich_api.version()
    except ApiError as err:
        return R.make(
            [R.check("photos.immich", "fail", str(err), "immich")],
            data,
            hints=["service_status(service='immich')"],
        )
    try:
        s = immich_api.statistics()
        data["library"] = {
            "photos": s.photos,
            "videos": s.videos,
            "size_gb": round(s.usage_bytes / GB, 1),
            "users": s.users,
        }
        queues = immich_api.queues()
        data["queues"] = {
            q.name: {"backlog": q.backlog, "failed": q.failed, "paused": q.is_paused}
            for q in queues
            if q.backlog or q.failed or q.is_paused
        }
        busy = [q for q in queues if q.backlog]
        for q in queues:
            if q.failed:
                checks.append(
                    R.check(
                        f"photos.queue.{q.name}",
                        "warn",
                        f"Immich {q.name}: {q.failed} failed jobs",
                        "immich",
                    )
                )
            if q.is_paused:
                checks.append(
                    R.check(
                        f"photos.queue.{q.name}.paused",
                        "warn",
                        f"Immich {q.name} queue is paused",
                        "immich",
                    )
                )
        data["working"] = (
            ", ".join(f"{q.name} ({q.backlog})" for q in busy) if busy else "idle"
        )
    except SecretMissing as err:
        checks.append(R.check("photos.key", "warn", str(err), "immich"))
        hints.append("homelab secrets set immich_api_key (an admin's key)")
    except ApiError as err:
        checks.append(R.check("photos.api", "fail", str(err), "immich"))
    tier = m.storage.tiers[m.photos.tier]
    vol = diskutil.volume(tier.mount)
    if vol is None:
        checks.append(
            R.check(
                "photos.tier",
                "fail",
                f"{m.photos.tier} is not mounted: the photo library is on it",
                "immich",
            )
        )
    else:
        u = diskutil.usage(vol)
        data["tier"] = {
            "name": m.photos.tier,
            "used_pct": u.used_pct,
            "free_gb": round(u.free / GB),
        }
    lib = data.get("library")
    return R.make(
        checks,
        data,
        ok_summary=(
            f"Immich {data['version']}: {lib['photos']} photos, "
            f"{lib['videos']} videos; jobs {data['working']}"
            if lib
            else f"Immich {data['version']}"
        ),
        hints=hints,
    )
