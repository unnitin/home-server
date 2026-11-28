"""Plex Media Server's local API: version, library sections, counts, new items.

The token goes in the X-Plex-Token header, never the URL, so it can't land in
an access log. `homelab secrets import-plex` can copy the server's own token
from its preferences into the Keychain, if you choose to.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from homelab.adapters.service_api import Client


def client() -> Client:
    return Client.for_service("plex", lambda token: {"X-Plex-Token": token})


@dataclass(frozen=True)
class Section:
    key: str
    title: str
    type: str  # movie, show, artist, photo
    paths: tuple[str, ...]
    scanned_at: Optional[int]  # epoch seconds
    refreshing: bool
    items: Optional[int] = None


@dataclass(frozen=True)
class Added:
    title: str
    year: Optional[int]
    type: str
    section: str
    added_at: Optional[int]


def version(c: Optional[Client] = None) -> str:
    mc = (c or client()).get("/identity", public=True).get("MediaContainer", {})
    return mc.get("version", "")


def sections(c: Optional[Client] = None, counts: bool = True) -> list[Section]:
    c = c or client()
    dirs = c.get("/library/sections").get("MediaContainer", {}).get("Directory", [])
    out = []
    for d in dirs:
        key = str(d.get("key", ""))
        items = None
        if counts and key:
            mc = c.get(
                f"/library/sections/{key}/all"
                "?X-Plex-Container-Start=0&X-Plex-Container-Size=0"
            ).get("MediaContainer", {})
            items = mc.get("totalSize", mc.get("size"))
        out.append(
            Section(
                key=key,
                title=d.get("title", ""),
                type=d.get("type", ""),
                paths=tuple(loc.get("path", "") for loc in d.get("Location", [])),
                scanned_at=d.get("scannedAt"),
                refreshing=bool(d.get("refreshing")),
                items=items,
            )
        )
    return out


def recently_added(limit: int = 5, c: Optional[Client] = None) -> list[Added]:
    mc = (
        (c or client())
        .get(
            "/library/recentlyAdded"
            f"?X-Plex-Container-Start=0&X-Plex-Container-Size={int(limit)}"
        )
        .get("MediaContainer", {})
    )
    return [
        Added(
            title=(
                f"{m['grandparentTitle']}: {m.get('title', '')}"
                if m.get("grandparentTitle")
                else m.get("title", "")
            ),
            year=m.get("year"),
            type=m.get("type", ""),
            section=m.get("librarySectionTitle", ""),
            added_at=m.get("addedAt"),
        )
        for m in mc.get("Metadata", [])[:limit]
    ]


@dataclass(frozen=True)
class Movie:
    key: str  # Plex's ratingKey
    title: str
    year: Optional[int]
    tmdb: Optional[str]
    matched: bool  # Plex's agent found it (not a local:// item)
    files: tuple[str, ...]
    labels: tuple[str, ...]
    added_at: Optional[int]


def movies(section: str, c: Optional[Client] = None) -> list[Movie]:
    c = c or client()
    mc = c.get(f"/library/sections/{section}/all?type=1&includeGuids=1").get(
        "MediaContainer", {}
    )
    out = []
    for m in mc.get("Metadata", []):
        guids = [g.get("id", "") for g in m.get("Guid", [])]
        tmdb = next(
            (g.split("://", 1)[1] for g in guids if g.startswith("tmdb://")), None
        )
        files = tuple(
            p.get("file", "")
            for media in m.get("Media", [])
            for p in media.get("Part", [])
        )
        out.append(
            Movie(
                key=str(m.get("ratingKey", "")),
                title=m.get("title", ""),
                year=m.get("year"),
                tmdb=tmdb,
                matched=not str(m.get("guid", "")).startswith("local://"),
                files=files,
                labels=tuple(lab.get("tag", "") for lab in m.get("Label", [])),
                added_at=m.get("addedAt"),
            )
        )
    return out
