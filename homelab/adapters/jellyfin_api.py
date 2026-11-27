"""Jellyfin's API (10.11): version, item counts, libraries, last library scan.

Needs an API key (Dashboard → API Keys). The key goes in the Authorization
header (`MediaBrowser Token="…"`), never the URL.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from homelab.adapters.service_api import Client


def client() -> Client:
    return Client.for_service(
        "jellyfin", lambda key: {"Authorization": f'MediaBrowser Token="{key}"'}
    )


@dataclass(frozen=True)
class Library:
    name: str
    type: str  # movies, tvshows, mixed …
    paths: tuple[str, ...]


@dataclass(frozen=True)
class Scan:
    status: str  # Completed, Failed, Cancelled, Aborted, or "" (never ran)
    ended: str  # ISO time, UTC
    state: str  # Idle or Running


def version(c: Optional[Client] = None) -> str:
    return (c or client()).get("/System/Info/Public", public=True).get("Version", "")


def counts(c: Optional[Client] = None) -> dict[str, int]:
    data = (c or client()).get("/Items/Counts")
    keys = ("MovieCount", "SeriesCount", "EpisodeCount", "BoxSetCount")
    return {k.removesuffix("Count").lower(): int(data.get(k, 0)) for k in keys}


def libraries(c: Optional[Client] = None) -> list[Library]:
    return [
        Library(
            name=f.get("Name", ""),
            type=f.get("CollectionType", "") or "mixed",
            paths=tuple(f.get("Locations") or ()),
        )
        for f in (c or client()).get("/Library/VirtualFolders")
    ]


def last_scan(c: Optional[Client] = None) -> Optional[Scan]:
    for task in (c or client()).get("/ScheduledTasks"):
        if task.get("Key") == "RefreshLibrary" or task.get("Name") == (
            "Scan Media Library"
        ):
            last = task.get("LastExecutionResult") or {}
            return Scan(
                status=last.get("Status", ""),
                ended=last.get("EndTimeUtc", ""),
                state=task.get("State", ""),
            )
    return None


@dataclass(frozen=True)
class Movie:
    id: str
    title: str
    year: Optional[int]
    tmdb: Optional[str]
    path: str
    tags: tuple[str, ...]


def movies(c: Optional[Client] = None) -> list[Movie]:
    data = (c or client()).get(
        "/Items?IncludeItemTypes=Movie&Recursive=true&Fields=ProviderIds,Path,Tags"
    )
    return [
        Movie(
            id=i.get("Id", ""),
            title=i.get("Name", ""),
            year=i.get("ProductionYear"),
            tmdb=(i.get("ProviderIds") or {}).get("Tmdb") or None,
            path=i.get("Path", ""),
            tags=tuple(i.get("Tags") or ()),
        )
        for i in data.get("Items", [])
    ]
