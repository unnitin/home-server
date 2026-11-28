"""A redacted support bundle: `python3 -m homelab bundle --since 24h`.

Run as a job by the logs_collect tool. Collects, redacting every line:
- the LaunchD job logs (/tmp/homelab-*.out|err, the manifest's
  storage.launchd_log_dir) changed within `since`, the last 2 MB of each;
- `launchctl print` for every io.homelab job;
- system_overview, service_status and storage_status (verbose), open
  incidents, the last 200 audit rows (without the Tailscale login) and the
  last 50 jobs.

Writes one .tgz beside the state database (bundles/), keeps the last 10, and
prints ::progress lines and a ::result line with its path and size.
"""

from __future__ import annotations

import io
import json
import tarfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from homelab import config, redact
from homelab.state import db, history

TAIL_BYTES = 2_000_000
KEEP = 10


def _tail(path: Path) -> str:
    with path.open("rb") as fh:
        fh.seek(0, 2)
        size = fh.tell()
        fh.seek(max(0, size - TAIL_BYTES))
        return fh.read().decode("utf-8", errors="replace")


def _add(tar: tarfile.TarFile, name: str, text: str) -> None:
    data = redact.redact(text).encode("utf-8")
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mtime = int(time.time())
    info.mode = 0o600
    tar.addfile(info, io.BytesIO(data))


def _json(value: Any) -> str:
    return json.dumps(redact.redact_obj(value), indent=2, default=str)


def build(
    since: str = "24h", out_dir: Path | None = None, log_dir: Path | None = None
) -> dict[str, Any]:
    from homelab import audit, jobs, tools
    from homelab.adapters import launchd

    m = config.load()
    window = history.seconds(since)
    out_dir = out_dir or db.path().parent / "bundles"
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    path = out_dir / f"homelab-logs-{stamp}.tgz"
    root = f"homelab-logs-{stamp}"
    cutoff = time.time() - window
    files = 0

    def progress(n: float, stage: str) -> None:
        print(f"::stage {stage}", flush=True)
        print(f"::progress {n:g}", flush=True)

    with tarfile.open(path, "w:gz") as tar:
        progress(5, "job logs")
        log_dir = log_dir or Path(m.storage.launchd_log_dir)
        for log in sorted(log_dir.glob("homelab-*")):
            if log.suffix in (".out", ".err") and log.stat().st_mtime >= cutoff:
                _add(tar, f"{root}/logs/{log.name}", _tail(log))
                files += 1
        progress(30, "launchd")
        for name, svc in m.services.items():
            if svc.launchd:
                j = launchd.job(svc.launchd)
                _add(tar, f"{root}/launchd/{svc.launchd}.json", _json(j.__dict__))
                files += 1
        progress(50, "status")
        for tool, args in (
            ("system_overview", {"verbose": True}),
            ("service_status", {"verbose": True}),
            ("storage_status", {"verbose": True}),
            ("incident_list", {"status": "open"}),
        ):
            _add(tar, f"{root}/{tool}.json", _json(tools.call(tool, **args)))
            files += 1
        progress(85, "audit and jobs")
        rows = audit.recent(200)
        for r in rows:
            r.pop("tailscale_user", None)
        _add(tar, f"{root}/audit.json", _json(rows))
        _add(tar, f"{root}/jobs.json", _json(jobs.jobs(limit=50)))
        files += 2
    for old in sorted(out_dir.glob("homelab-logs-*.tgz"))[:-KEEP]:
        old.unlink()
    path.chmod(0o600)
    result = {"path": str(path), "bytes": path.stat().st_size, "files": files}
    print("::result " + json.dumps(result), flush=True)
    progress(100, "done")
    return result
