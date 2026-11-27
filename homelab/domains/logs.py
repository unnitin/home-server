"""Log tails and log search, redacted and marked as untrusted data.

Sources: each LaunchD job's stdout and stderr (paths from its plist template
in launchd/), a compose service's container logs, and the module logs under
storage.log_root when its tier is mounted. Log lines can carry text an
attacker controls (file names in staging, container output), so they come
back wrapped as data, never as instructions (04).
"""

from __future__ import annotations

import os
import plistlib
import re
import time
from pathlib import Path
from typing import Any, Optional

from homelab import config
from homelab import result as R
from homelab.adapters import diskutil, docker

MAX_LINES = 500
SEARCH_MAX_MATCHES = 200
TAIL_BLOCK = 65536


def job_logs(label: str) -> dict[str, Path]:
    """stdout/stderr paths from launchd/<label>.plist (the template)."""
    path = config.REPO / "launchd" / f"{label}.plist"
    try:
        plist = plistlib.loads(path.read_bytes())
    except (OSError, plistlib.InvalidFileException):
        return {}
    out = {}
    for key, stream in (("StandardOutPath", "stdout"), ("StandardErrorPath", "stderr")):
        value = plist.get(key)
        if isinstance(value, str) and "__" not in value:
            out[stream] = Path(value)
    return out


def tail(path: Path, lines: int) -> list[str]:
    """The last `lines` lines of a file, read from its end (logs can be GBs)."""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            end = f.tell()
            data, pos = b"", end
            while pos > 0 and data.count(b"\n") <= lines:
                step = min(TAIL_BLOCK, pos)
                pos -= step
                f.seek(pos)
                data = f.read(step) + data
    except OSError:
        return []
    text = data.decode("utf-8", errors="replace").splitlines()
    return text[-lines:] if lines else []


def _filter(lines: list[str], grep: Optional[str]) -> list[str]:
    if not grep:
        return lines
    needle = grep.lower()  # plain text, not a regex: no pattern can stall the server
    return [line for line in lines if needle in line.lower()]


def service_logs(
    service: str,
    lines: int = 100,
    grep: Optional[str] = None,
    container: Optional[str] = None,
) -> dict:
    m = config.load()
    if service not in m.services:
        return R.error(
            f"unknown service {service!r}; use one of {', '.join(m.boot_order)}"
        )
    lines = max(1, min(int(lines), MAX_LINES))
    svc = m.services[service]
    sources: dict[str, Any] = {}
    if container or svc.kind == "compose":
        if svc.kind != "compose" or not svc.compose_dir:
            return R.error(f"{service} has no containers")
        project = docker.compose_ps(
            config.REPO / svc.compose_dir / "docker-compose.yml"
        )
        names = [c.name for c in project.containers]
        wanted = [container] if container else names
        if container and container not in names:
            return R.error(
                f"no container {container!r} in {service}; it has: {', '.join(names)}"
            )
        for name in wanted:
            text = docker.logs(name, lines)
            if text is not None:
                sources[f"container:{name}"] = _filter(text.splitlines()[-lines:], grep)
    for stream, path in job_logs(svc.launchd).items():
        if path.exists():
            sources[f"{stream}:{path}"] = _filter(tail(path, lines), grep)
    if not sources:
        return R.error(
            f"no logs found for {service}",
            [f"service_status(service='{service}')"],
        )
    data = {
        "service": service,
        "lines": lines,
        "grep": grep,
        "logs": [R.untrusted(src, body) for src, body in sources.items()],
    }
    total = sum(len(b) for b in sources.values())
    return R.make(
        [],
        data,
        summary=f"{total} lines from {len(sources)} sources for {service}"
        + (f" matching {grep!r}" if grep else ""),
        hints=["logs_search(query=...) searches every log"],
    )


def parse_since(since: str) -> float:
    m = re.fullmatch(r"(\d+)\s*([mhd])", since.strip())
    if not m:
        raise ValueError(f"since is like 30m, 24h or 7d: {since!r}")
    return int(m.group(1)) * {"m": 60, "h": 3600, "d": 86400}[m.group(2)]


def log_files(m: config.Manifest) -> dict[str, list[Path]]:
    files: dict[str, list[Path]] = {"launchd": [], "modules": []}
    for svc in m.services.values():
        files["launchd"] += [p for p in job_logs(svc.launchd).values() if p.exists()]
    root = m.storage.log_root
    tier = next((t for t in m.storage.tiers.values() if root.startswith(t.mount)), None)
    if tier is None or diskutil.volume(tier.mount) is not None:
        files["modules"] = sorted(Path(root).glob("*/*.log"))
    return files


def logs_search(query: str, since: str = "24h", sources: Optional[list[str]] = None):
    if not query or len(query) < 3:
        return R.error("query needs at least 3 characters")
    try:
        window = parse_since(since)
    except ValueError as err:
        return R.error(str(err))
    m = config.load()
    groups = log_files(m)
    chosen = sources or list(groups)
    cutoff = time.time() - window
    needle = query.lower()
    matches: list[dict[str, Any]] = []
    searched = 0
    for group in chosen:
        for path in groups.get(group, []):
            try:
                if path.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            searched += 1
            for n, line in enumerate(tail(path, 20000), 1):
                if needle in line.lower():
                    matches.append({"source": str(path), "line": line[:400]})
                    if len(matches) >= SEARCH_MAX_MATCHES:
                        break
    note = []
    if "modules" in chosen and not groups["modules"]:
        note.append("module logs are on an unmounted tier and weren't searched")
    return R.make(
        [],
        {
            "query": query,
            "since": since,
            "files_searched": searched,
            "matches": R.untrusted("logs", matches),
            **({"note": "; ".join(note)} if note else {}),
        },
        summary=f"{len(matches)} matches for {query!r} in {searched} files "
        f"changed in {since}",
    )
