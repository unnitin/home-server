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
