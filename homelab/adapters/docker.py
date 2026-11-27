"""Containers of a compose project, from `docker compose ps` and `docker inspect`."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from homelab import exec as hexec


@dataclass(frozen=True)
class Container:
    name: str
    service: str
    state: str  # running, exited, restarting …
    health: str  # healthy, unhealthy, starting, "" (no healthcheck)
    image: str
    status: str  # docker's own text, e.g. "Up 3 weeks (healthy)"
    restarts: int = 0
    started: str = ""
    exit_code: int = 0

    @property
    def ok(self) -> bool:
        return self.state == "running" and self.health in ("healthy", "")


@dataclass(frozen=True)
class Project:
    runtime: bool  # the docker CLI answered at all
    containers: tuple[Container, ...] = ()
    error: str = ""


def _lines(text: str) -> list[dict]:
    """compose ps --format json: one object per line (or one array, in old versions)."""
    text = text.strip()
    if text.startswith("["):
        return json.loads(text)
    return [json.loads(line) for line in text.splitlines() if line.startswith("{")]


def compose_ps(compose_file: Path) -> Project:
    if not hexec.available("docker"):
        return Project(runtime=False, error="docker CLI not installed")
    r = hexec.run(
        ["docker", "compose", "-f", str(compose_file), "ps", "-a", "--format", "json"],
        timeout=20,
    )
    if not r.ok:
        reason = (r.stderr or r.stdout).strip().splitlines()
        return Project(runtime=False, error=reason[-1] if reason else f"rc {r.rc}")
    rows = _lines(r.stdout)
    detail = inspect([row["Name"] for row in rows]) if rows else {}
    containers = []
    for row in rows:
        extra = detail.get(row["Name"], {})
        containers.append(
            Container(
                name=row["Name"],
                service=row.get("Service", ""),
                state=row.get("State", ""),
                health=row.get("Health", "") or "",
                image=row.get("Image", ""),
                status=row.get("Status", ""),
                restarts=int(extra.get("RestartCount", 0)),
                started=(extra.get("State") or {}).get("StartedAt", ""),
                exit_code=int(row.get("ExitCode", 0) or 0),
            )
        )
    return Project(runtime=True, containers=tuple(containers))


def inspect(names: list[str]) -> dict[str, dict]:
    r = hexec.run(["docker", "inspect", *sorted(names)], timeout=20)
    if not r.ok:
        return {}
    try:
        return {c["Name"].lstrip("/"): c for c in json.loads(r.stdout)}
    except (json.JSONDecodeError, KeyError, TypeError):
        return {}


def logs(name: str, lines: int) -> Optional[str]:
    """The container's last lines, or None if docker can't give them.

    docker logs replays the container's stderr on stderr: both are kept.
    """
    r = hexec.run(["docker", "logs", "--tail", str(lines), name], timeout=20)
    return r.stdout + r.stderr if r.ok else None
