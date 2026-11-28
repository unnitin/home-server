"""Immich's API (v2): version, library statistics and background job queues.

Statistics and jobs need an admin's API key (Account settings → API keys).
Per-user statistics carry people's names, so only totals are returned.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from homelab.adapters.service_api import Client


def client() -> Client:
    return Client.for_service("immich", lambda key: {"x-api-key": key})


@dataclass(frozen=True)
class Stats:
    photos: int
    videos: int
    usage_bytes: int
    users: int


@dataclass(frozen=True)
class Queue:
    name: str
    active: int
    waiting: int
    failed: int
    delayed: int
    paused: int
    is_active: bool
    is_paused: bool

    @property
    def backlog(self) -> int:
        return self.active + self.waiting + self.delayed


def version(c: Optional[Client] = None) -> str:
    v = (c or client()).get("/server/version", public=True)
    return f"{v.get('major', 0)}.{v.get('minor', 0)}.{v.get('patch', 0)}"


def statistics(c: Optional[Client] = None) -> Stats:
    s = (c or client()).get("/server/statistics")
    return Stats(
        photos=int(s.get("photos", 0)),
        videos=int(s.get("videos", 0)),
        usage_bytes=int(s.get("usage", 0)),
        users=len(s.get("usageByUser") or []),
    )


def queues(c: Optional[Client] = None) -> list[Queue]:
    data = (c or client()).get("/jobs")
    out = []
    for name, q in sorted(data.items()):
        counts = q.get("jobCounts") or {}
        status = q.get("queueStatus") or {}
        out.append(
            Queue(
                name=name,
                active=int(counts.get("active", 0)),
                waiting=int(counts.get("waiting", 0)),
                failed=int(counts.get("failed", 0)),
                delayed=int(counts.get("delayed", 0)),
                paused=int(counts.get("paused", 0)),
                is_active=bool(status.get("isActive")),
                is_paused=bool(status.get("isPaused")),
            )
        )
    return out


# --- curation reports (read-only; 08-curation.md) --------------------------------
# Only ids, dates, city/country, people's names and album names leave here:
# never GPS coordinates, never an image.


@dataclass(frozen=True)
class Album:
    id: str
    name: str
    assets: int
    shared: bool
    owned: bool
    start: str  # ISO date of the earliest photo, "" when empty
    end: str


@dataclass(frozen=True)
class Asset:
    id: str
    type: str  # IMAGE or VIDEO
    taken: str  # ISO date-time
    city: str
    country: str
    people: tuple[str, ...]


def _album(a: dict, me: str) -> Album:
    return Album(
        id=a.get("id", ""),
        name=a.get("albumName", ""),
        assets=int(a.get("assetCount", 0)),
        shared=bool(a.get("shared")),
        owned=(a.get("ownerId") == me) if me else True,
        start=(a.get("startDate") or "")[:10],
        end=(a.get("endDate") or "")[:10],
    )


def _asset(a: dict) -> Asset:
    exif = a.get("exifInfo") or {}
    return Asset(
        id=a.get("id", ""),
        type=a.get("type", ""),
        taken=exif.get("dateTimeOriginal") or a.get("fileCreatedAt") or "",
        city=exif.get("city") or "",
        country=exif.get("country") or "",
        people=tuple(p.get("name") for p in a.get("people") or [] if p.get("name")),
    )


def me(c: Optional[Client] = None) -> str:
    return (c or client()).get("/users/me").get("id", "")


def albums(c: Optional[Client] = None) -> list[Album]:
    c = c or client()
    mine = me(c)
    seen: dict[str, Album] = {}
    for shared in ("false", "true"):
        for a in c.get(f"/albums?shared={shared}"):
            seen.setdefault(a.get("id", ""), _album(a, mine))
    return sorted(seen.values(), key=lambda a: a.name.lower())


def album_assets(
    album_id: str, c: Optional[Client] = None
) -> tuple[Album, list[Asset]]:
    c = c or client()
    a = c.get(f"/albums/{album_id}?withoutAssets=false")
    return _album(a, ""), [_asset(x) for x in a.get("assets") or []]


def not_in_album(taken_after: str, limit: int = 1000, c: Optional[Client] = None):
    """Photos and videos in no album, taken after an ISO date (metadata search)."""
    c = c or client()
    found: list[Asset] = []
    page = 1
    while len(found) < limit:
        body = {
            "isNotInAlbum": True,
            "takenAfter": taken_after,
            "withExif": True,
            "withPeople": True,
            "size": min(250, limit - len(found)),
            "page": page,
        }
        assets = c.post("/search/metadata", body).get("assets") or {}
        found += [_asset(x) for x in assets.get("items") or []]
        nxt = assets.get("nextPage")
        if not nxt:
            break
        page = int(nxt)
    return found
