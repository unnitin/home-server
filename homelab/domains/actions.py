"""The safe actions (T1, docs/mcp-refactor/03 and 05).

Every action:
- takes `dry_run`, true by default, and when dry says exactly what it would do;
- checks its guards first, dry run included: the tiers and services the
  manifest says it needs (`depends_on`, `data_tier`, the media tier);
- runs only through homelab.exec, and anything slow as a job;
- respects its lock from config/policy.yaml: a job on the same lock queues
  behind the running one, a quick action on a busy lock is refused.

Nothing here can erase, delete or format: the T3 commands aren't on the exec
allowlist at all. Restarting the MCP server itself, Tailscale (the connection
the call came over) or Colima (every container) is refused, with the command
for a person to run instead.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any, Optional

from homelab import config, jobs, policy
from homelab import exec as hexec
from homelab import result as R
from homelab.adapters import diskutil, immich_api, jellyfin_api, launchd, plex_api
from homelab.adapters import http as hhttp
from homelab.adapters import system, tailscale
from homelab.adapters.service_api import ApiError
from homelab.domains import governance, media, services
from homelab.sudoers import rules as sudo_rules

REPO = config.REPO
DRY_HINT = "Call again with dry_run=false to do it"
MEDIA_PASS = {
    "all": "--all",
    "movies": "--movies-only",
    "tv": "--tv-only",
    "collections": "--collections-only",
}
IMMICH_JOBS = (
    "thumbnailGeneration",
    "metadataExtraction",
    "smartSearch",
    "faceDetection",
    "duplicateDetection",
)
SERVE_WAIT = 2  # seconds a backend gets to answer before its mapping is skipped


# --- shared ---------------------------------------------------------------------


def _plan(
    tool: str,
    summary: str,
    steps: list[str],
    data: Optional[dict] = None,
    checks: Optional[list] = None,
) -> dict:
    return R.make(
        checks or [],
        {"dry_run": True, "plan": steps, **(data or {})},
        summary=summary,
        hints=[DRY_HINT],
        status=None,  # ok, or warn when a guard warns (a soft tier missing)
    )


def _refused(
    tool: str,
    reason: str,
    checks: Optional[list] = None,
    hints: tuple = (),
    data: Optional[dict] = None,
) -> dict:
    checks = list(checks or []) or [R.check(f"{tool}.refused", "fail", reason, tool)]
    return R.make(
        checks,
        {"refused": True, **(data or {})},
        summary=f"Refused: {reason}",
        hints=hints,
        status="fail",
        verbose=True,
    )


def _started(
    job: dict,
    summary: str,
    data: Optional[dict] = None,
    checks: Optional[list] = None,
) -> dict:
    res = R.make(
        [c for c in checks or [] if c["status"] != "ok"],  # warnings stay visible
        {"job": governance.job_view(job), **(data or {})},
        summary=summary,
        hints=[f"Call job_status(job_id='{job['id']}') in about a minute"],
        status="pending",
    )
    res["job_id"] = job["id"]
    return res


def _lock(tool: str, args: dict[str, Any]) -> Optional[str]:
    return policy.load().lock_key(tool, args)


def _mounted(m: config.Manifest, tier: str) -> bool:
    return diskutil.volume(m.storage.tiers[tier].mount) is not None


def service_up(m: config.Manifest, name: str) -> bool:
    """The service itself answers: its health URL or command, else its job runs."""
    svc = m.services[name]
    if svc.health and svc.health.http:
        return bool(services.probe(svc.health.http, svc.health.expect)["ok"])
    if svc.health and svc.health.cmd:
        return hexec.run(svc.health.cmd, timeout=10).ok
    if svc.launchd:
        return launchd.job(svc.launchd).running
    return False


def guard_checks(
    m: config.Manifest, needs: list[str], soft: tuple | list = ()
) -> list[dict]:
    """One check per dependency: a tier must be mounted, a service up. A `soft`
    tier missing is a warning: the action goes ahead without it."""
    checks = []
    for need in dict.fromkeys(soft):
        if need in m.storage.tiers and not _mounted(m, need):
            checks.append(
                R.check(
                    f"guard.{need}.mounted",
                    "warn",
                    f"{need} is not mounted: what's on it stays offline",
                    need,
                )
            )
    for need in dict.fromkeys(needs):  # in order, once each
        if need in m.storage.tiers:
            up = _mounted(m, need)
            text = f"{need} is mounted" if up else f"{need} is not mounted"
            checks.append(
                R.check(f"guard.{need}.mounted", "ok" if up else "fail", text, need)
            )
        elif need in m.services:
            up = service_up(m, need)
            text = f"{need} is up" if up else f"{need} is down"
            checks.append(
                R.check(f"guard.{need}.up", "ok" if up else "fail", text, need)
            )
    return checks


def _guards_fail(checks: list[dict]) -> bool:
    return any(c["status"] == "fail" for c in checks)


def _needs(m: config.Manifest, name: str) -> tuple[list[str], list[str]]:
    """What starting the service requires, and what it uses but starts without.

    A native app starts once its own data tier is mounted, as its LaunchD job
    does (lib/native_app.sh): its media tier being away leaves those libraries
    offline, nothing worse, and refusing would leave no way to restart it. Every
    other kind needs everything it depends on.
    """
    svc = m.services[name]
    deps = list(svc.depends_on)
    if svc.kind == "native_app":
        hard = ([svc.data_tier] if svc.data_tier else []) + [
            d for d in deps if d in m.services
        ]
        soft = [d for d in deps if d in m.storage.tiers and d != svc.data_tier]
        return hard, soft
    return deps + ([svc.data_tier] if svc.data_tier else []), []


def _not_here(m: config.Manifest, tool: str, name: str) -> Optional[dict]:
    """Services no action may restart or start from here, and why."""
    svc = m.services[name]
    label = svc.launchd or ""
    if name == "mcp":
        return _refused(
            tool,
            "the MCP server can't restart itself: that would end this call",
            hints=(f"On the mini: launchctl kickstart -k gui/$(id -u)/{label}",),
        )
    if svc.kind == "daemon":
        return _refused(
            tool,
            "Tailscale carries this connection: restart it on the mini itself",
        )
    if svc.kind == "runtime":
        return _refused(
            tool,
            f"{name} is the Docker VM: restarting or starting it affects every "
            "container, so it's for a person to do",
            hints=("On the mini: colima status, then colima start or colima restart",),
        )
    return None


def _kickstart_argv(label: str, restart: bool) -> list[str]:
    return [
        "launchctl",
        "kickstart",
        *(["-k"] if restart else []),
        f"{launchd.domain()}/{label}",
    ]


def _job_gate(tool: str, label: str) -> tuple[Optional[launchd.Job], Optional[dict]]:
    j = launchd.job(label)
    if j.held:
        return j, _refused(
            tool,
            f"{label} is held (launchctl disable): releasing it is your decision",
            hints=(f"launchctl enable gui/$(id -u)/{label}, then bootstrap it",),
        )
    if not j.loaded:
        return j, _refused(
            tool,
            f"{label} isn't loaded",
            hints=(
                f"On the mini: scripts/automation/configure_launchd.sh "
                f"{label.removeprefix('io.homelab.')}",
            ),
        )
    return j, None


def _run_sync(tool: str, argv: list[str], done: str, timeout: float = 30) -> dict:
    r = hexec.run(argv, timeout=timeout)
    if r.ok:
        return R.make([], {"ran": " ".join(argv)}, summary=done)
    detail = (r.stderr or r.stdout).strip()[:160] or f"exit {r.rc}"
    return R.make(
        [R.check(f"{tool}.failed", "fail", f"{' '.join(argv[:3])}…: {detail}", tool)],
        {"ran": " ".join(argv), "rc": r.rc},
        status="fail",
    )


# --- services --------------------------------------------------------------------


def service_restart(service: str, dry_run: bool = True) -> dict:
    m = config.load()
    if service not in m.services:
        return R.error(f"unknown service {service!r}")
    svc = m.services[service]
    refused = _not_here(m, "service_restart", service)
    if refused:
        return refused
    checks = guard_checks(m, *_needs(m, service))
    if _guards_fail(checks):
        return _refused(
            "service_restart", f"{service} needs what isn't there", checks=checks
        )
    lock = _lock("service_restart", {"service": service})

    if svc.kind == "native_app":
        script = REPO / "scripts" / "services" / "restart_native_app.sh"
        argv = ["bash", str(script), service]
        steps = [
            f"Quit {svc.app}: TERM to its processes, KILL after 30 s",
            f"Start it as its LaunchD job does and wait for {svc.health.http}"
            if svc.health and svc.health.http
            else f"Start {svc.app}",
            "Put the tailnet mappings back from the manifest",
        ]
    elif svc.kind == "compose":
        compose = REPO / (svc.compose_dir or "") / "docker-compose.yml"
        argv = ["docker", "compose", "-f", str(compose), "restart"]
        steps = [
            f"docker compose restart: restarts {service}'s containers as they "
            "are (no pull, no recreate, no new settings)"
        ]
    elif svc.launchd:
        j, gate = _job_gate("service_restart", svc.launchd)
        if gate:
            return gate
        argv = _kickstart_argv(svc.launchd, restart=True)
        steps = [f"launchctl kickstart -k {svc.launchd}: stop the job and run it again"]
        if dry_run:
            return _plan(
                "service_restart", f"Would restart {service}", steps, checks=checks
            )
        return _run_sync("service_restart", argv, f"Restarted {svc.launchd}")
    else:
        return R.error(f"{service} has nothing to restart")

    if dry_run:
        return _plan(
            "service_restart",
            f"Would restart {service} ({len(steps)} steps, " "as a job)",
            steps,
            checks=checks,
        )
    job = jobs.submit(
        "service_restart",
        argv,
        tool="service_restart",
        args={"service": service},
        lock=lock,
        timeout=300,
    )
    return _started(job, f"Restarting {service}: job {job['id']}", checks=checks)


def service_start(service: str, dry_run: bool = True) -> dict:
    m = config.load()
    if service not in m.services:
        return R.error(f"unknown service {service!r}")
    svc = m.services[service]
    refused = _not_here(m, "service_start", service)
    if refused:
        return refused
    if svc.kind in ("native_app", "compose", "process") and service_up(m, service):
        return R.make(
            [],
            {"already_up": True},
            summary=f"{service} is already up: " "nothing to do",
        )
    checks = guard_checks(m, *_needs(m, service))
    if _guards_fail(checks):
        return _refused(
            "service_start", f"{service} needs what isn't there", checks=checks
        )
    lock = _lock("service_start", {"service": service})

    if svc.kind == "native_app":
        script = REPO / "scripts" / "services" / f"start_{service}_safe.sh"
        argv = ["bash", str(script)]
        steps = [f"open {svc.app} (its data tier is mounted) and wait for it to answer"]
    elif svc.kind == "compose":
        compose = REPO / (svc.compose_dir or "") / "docker-compose.yml"
        argv = ["docker", "compose", "-f", str(compose), "start"]
        steps = [
            f"docker compose start: starts {service}'s stopped containers as they "
            "are (no pull, no recreate)"
        ]
    elif svc.launchd:
        j, gate = _job_gate("service_start", svc.launchd)
        if gate:
            return gate
        if j and j.running:
            return R.make(
                [], {"already_up": True}, summary=f"{svc.launchd} is already running"
            )
        argv = _kickstart_argv(svc.launchd, restart=False)
        steps = [f"launchctl kickstart {svc.launchd}: run the job now"]
        if dry_run:
            return _plan(
                "service_start", f"Would start {service}", steps, checks=checks
            )
        return _run_sync("service_start", argv, f"Started {svc.launchd}")
    else:
        return R.error(f"{service} has nothing to start")

    if dry_run:
        return _plan(
            "service_start", f"Would start {service} (as a job)", steps, checks=checks
        )
    job = jobs.submit(
        "service_start",
        argv,
        tool="service_start",
        args={"service": service},
        lock=lock,
        timeout=300,
    )
    return _started(job, f"Starting {service}: job {job['id']}", checks=checks)


def launchd_kickstart(label: str, dry_run: bool = True) -> dict:
    m = config.load()
    labels = {s.launchd: n for n, s in m.services.items() if s.launchd}
    if label not in labels:
        return R.error(f"unknown job {label!r}", data={"jobs": sorted(labels)})
    if label in hexec.KICK_NEVER:
        return _refused(
            "launchd_kickstart",
            "the MCP server can't restart itself: that would end this call",
            hints=(f"On the mini: launchctl kickstart -k gui/$(id -u)/{label}",),
        )
    j, gate = _job_gate("launchd_kickstart", label)
    if gate:
        return gate
    restart = bool(j and j.running)
    argv = _kickstart_argv(label, restart=restart)
    what = "stop the running job and run it again" if restart else "run it now"
    steps = [f"launchctl kickstart{' -k' if restart else ''} {label}: {what}"]
    svc = m.services[labels[label]]
    if svc.kind == "native_app":
        steps.append(f"{svc.app} itself keeps running: service_restart restarts it")
    if dry_run:
        return _plan("launchd_kickstart", f"Would {what}: {label}", steps)
    return _run_sync(
        "launchd_kickstart",
        argv,
        f"Kickstarted {label} ({'restarted' if restart else 'started'})",
    )


# --- media -----------------------------------------------------------------------


def _media_root(m: config.Manifest) -> Path:
    return Path(m.storage.tiers[m.media.tier].mount)


def media_process(library: str = "all", dry_run: bool = True) -> dict:
    m = config.load()
    if library != "all" and library not in m.media.libraries:
        return R.error(f"unknown library {library!r}")
    checks = guard_checks(m, [m.media.tier])
    if _guards_fail(checks):
        return _refused(
            "media_process",
            f"{m.media.tier} holds staging and the " "libraries",
            checks=checks,
        )
    flag = MEDIA_PASS.get(library) or f"--{library}-only"
    argv = ["bash", str(REPO / "scripts" / "media" / "processor.sh"), flag]
    lock = _lock("media_process", {"library": library})
    if dry_run:
        staged = media.staging_list(library, include_failed=False)
        waiting = {
            lib: d["waiting"] for lib, d in staged["data"].get("libraries", {}).items()
        }
        busy = (
            " (queued behind the media job running now)"
            if jobs.held(f"res-{lock}")
            else ""
        )
        return _plan(
            "media_process",
            f"Would process {sum(waiting.values())} staged files ({library}){busy}",
            [
                f"scripts/media/processor.sh {flag}: rename and move staged files into "
                "the libraries; files it can't parse go to staging/failed"
            ],
            {"waiting": waiting},
            checks=checks,
        )
    job = jobs.submit(
        "media_process",
        argv,
        tool="media_process",
        args={"library": library},
        lock=lock,
        timeout=7200,
    )
    queued = (
        " (queued behind the running media job)"
        if job["state"] == "queued" and jobs.held(f"res-{lock}")
        else ""
    )
    return _started(job, f"Processing {library} staging: job {job['id']}{queued}")


DAY = re.compile(r"^\d{8}$")


def media_retry_failed(
    library: str, date: Optional[str] = None, dry_run: bool = True
) -> dict:
    m = config.load()
    if library not in m.media.libraries:
        return R.error(
            f"pick the library the files belong to: " f"{', '.join(m.media.libraries)}"
        )
    if date is not None and not DAY.match(date):
        return R.error("date is the failed folder's name, YYYYMMDD")
    checks = guard_checks(m, [m.media.tier])
    if _guards_fail(checks):
        return _refused(
            "media_retry_failed", f"{m.media.tier} holds staging", checks=checks
        )
    root = _media_root(m)
    failed_root = root / m.media.failed
    target = root / m.media.staging / m.media.libraries[library].staging
    days = (
        [failed_root / date]
        if date
        else sorted(
            p for p in failed_root.iterdir() if p.is_dir() and DAY.match(p.name)
        )
        if failed_root.is_dir()
        else []
    )
    files = [
        f
        for d in days
        if d.is_dir()
        for f in sorted(d.iterdir())
        if f.is_file() and not f.name.startswith(".")
    ]
    moves = [(f, target / f.name) for f in files]
    clash = [f.name for f, t in moves if t.exists()]
    moves = [(f, t) for f, t in moves if not t.exists()]
    names = R.untrusted(
        "file names", [f"{f.parent.name}/{f.name}" for f, _ in moves][:50]
    )
    if not moves:
        return R.make(
            [],
            {"moved": 0, "skipped": R.untrusted("file names", clash)},
            summary="No failed files to retry" + (f" from {date}" if date else ""),
        )
    lock = _lock("media_retry_failed", {"library": library})
    if dry_run:
        return _plan(
            "media_retry_failed",
            f"Would move {len(moves)} failed files back to {library} staging, then "
            "process it",
            [
                f"Move each file from {m.media.failed}/<date>/ to "
                f"{m.media.staging}/{m.media.libraries[library].staging}/",
                f"Then media_process(library='{library}') as a job",
            ],
            {"files": names, "skipped_exists": len(clash)},
            checks=checks,
        )
    with jobs.lock_now(f"res-{lock}") as free:
        if not free:
            return _refused(
                "media_retry_failed",
                "a media job is running: retry " "after it",
                hints=("job_list(state='running')",),
            )
        target.mkdir(exist_ok=True)  # under staging, on the mounted media tier
        moved = 0
        for src, dst in moves:
            os.rename(src, dst)  # one volume: a rename, never a copy
            moved += 1
    flag = MEDIA_PASS[library]
    job = jobs.submit(
        "media_process",
        ["bash", str(REPO / "scripts" / "media" / "processor.sh"), flag],
        tool="media_retry_failed",
        args={"library": library, "date": date},
        lock=lock,
        timeout=7200,
    )
    return _started(
        job,
        f"Moved {moved} files back to {library} staging; processing: "
        f"job {job['id']}",
        {"moved": moved, "files": names},
    )


def library_scan(server: str = "both", dry_run: bool = True) -> dict:
    m = config.load()
    servers = ["plex", "jellyfin"] if server == "both" else [server]
    needs = [m.media.tier, *servers]
    checks = guard_checks(m, needs)
    if _guards_fail(checks):
        # A scan with the media tier missing would show Plex and Jellyfin empty
        # folders, and they may drop the items they can't find.
        return _refused(
            "library_scan",
            "a scan needs the media tier mounted and the " "server up",
            checks=checks,
        )
    steps = []
    if "plex" in servers:
        steps.append("Plex: refresh every library section")
    if "jellyfin" in servers:
        steps.append("Jellyfin: scan all libraries")
    if dry_run:
        return _plan(
            "library_scan", f"Would scan {' and '.join(servers)}", steps, checks=checks
        )
    done, problems = [], []
    for name in servers:
        try:
            if name == "plex":
                plex_api.client().act("GET", "/library/sections/all/refresh")
            else:
                jellyfin_api.client().act("POST", "/Library/Refresh")
            done.append(name)
        except ApiError as err:
            problems.append(
                R.check(f"library_scan.{name}", "fail", str(err)[:180], name)
            )
    if problems:
        return R.make(
            problems,
            {"started": done},
            status="fail",
            hints=["python3 -m homelab secrets list"],
        )
    return R.make(
        [],
        {"started": done},
        summary=f"Scan started on {' and '.join(done)}"
        "; media_library_stats shows when it's done",
    )


def photos_run_job(job: str, mode: str = "missing", dry_run: bool = True) -> dict:
    m = config.load()
    if job not in IMMICH_JOBS:
        return R.error(f"unknown Immich job {job!r}", data={"jobs": list(IMMICH_JOBS)})
    checks = guard_checks(m, ["immich", m.photos.tier])
    if _guards_fail(checks):
        return _refused(
            "photos_run_job",
            "Immich must be up with its library " "mounted",
            checks=checks,
        )
    what = "every photo again" if mode == "all" else "the photos it hasn't done yet"
    if dry_run:
        try:
            queue = next((q for q in immich_api.queues() if q.name == job), None)
        except ApiError as err:
            return _refused(
                "photos_run_job",
                str(err)[:180],
                hints=("python3 -m homelab secrets set immich_api_key",),
            )
        data = {"queue": queue.__dict__ if queue else None}
        return _plan(
            "photos_run_job",
            f"Would start Immich {job} on {what}",
            [f"Immich: start {job} ({mode})"],
            data,
            checks=checks,
        )
    try:
        immich_api.client().act(
            "PUT", f"/jobs/{job}", {"command": "start", "force": mode == "all"}
        )
    except ApiError as err:
        return R.make(
            [R.check("photos_run_job.failed", "fail", str(err)[:180], "immich")],
            status="fail",
        )
    return R.make(
        [],
        {"job": job, "mode": mode},
        summary=f"Immich {job} started on " f"{what}; photos_stats shows the backlog",
    )


# --- the tailnet, storage, power, logs -------------------------------------------


def tailscale_serve_reconcile(dry_run: bool = True) -> dict:
    m = config.load()
    live = tailscale.serve()
    if live is None:
        return R.make(
            [
                R.check(
                    "serve.unreadable",
                    "fail",
                    "tailscale serve status " "can't be read",
                    "tailscale",
                )
            ],
            status="fail",
        )
    wanted = {mp.https: mp.target for mp in m.remote_access.tailscale_serve}
    service_of = {mp.https: mp.service for mp in m.remote_access.tailscale_serve}
    d = tailscale.drift(live, wanted)
    todo = list(d.missing) + [p for p, _, _ in d.wrong]
    checks = []
    for p in d.extra:
        checks.append(
            R.check(
                f"serve.{p}.extra",
                "warn",
                f":{p} is served but isn't " "in the manifest: left alone",
                "tailscale",
            )
        )
    for p in d.funnel:
        checks.append(
            R.check(
                f"serve.{p}.funnel",
                "fail",
                f":{p} is on Funnel " "(the internet): turn it off on the mini",
                "tailscale",
            )
        )
    if not todo:
        return R.make(
            checks,
            {"changed": []},
            ok_summary="Every tailnet mapping matches the manifest",
        )
    plan = []
    for p in sorted(todo):
        up = hhttp.get(wanted[p], timeout=SERVE_WAIT).status is not None
        plan.append(
            {
                "https": p,
                "target": wanted[p],
                "service": service_of[p],
                "backend_up": up,
            }
        )
    if dry_run:
        steps = [
            f":{x['https']} -> {x['target']} ({x['service']})"
            + ("" if x["backend_up"] else ": backend down, would be skipped")
            for x in plan
        ]
        return _plan(
            "tailscale_serve_reconcile",
            f"Would map {len(plan)} ports",
            steps,
            {"mappings": plan},
            checks=checks,
        )
    with jobs.lock_now("res-serve") as free:
        if not free:
            return _refused("tailscale_serve_reconcile", "another reconcile is running")
        changed = []
        for x in plan:
            if not x["backend_up"]:
                checks.append(
                    R.check(
                        f"serve.{x['https']}.skipped",
                        "warn",
                        f"{x['service']} isn't answering: :{x['https']} "
                        "left unmapped",
                        "tailscale",
                    )
                )
                continue
            r = hexec.run(
                ["tailscale", "serve", "--bg", f"--https={x['https']}", x["target"]],
                timeout=30,
            )
            if r.ok:
                changed.append(x["https"])
            else:
                checks.append(
                    R.check(
                        f"serve.{x['https']}.failed",
                        "fail",
                        (r.stderr or r.stdout).strip()[:150] or f"exit {r.rc}",
                        "tailscale",
                    )
                )
    return R.make(
        checks,
        {"changed": changed},
        ok_summary=f"Mapped {len(changed)} ports from the manifest",
    )


CREATED = re.compile(r"(?:Would create|Created) (/\S.*?) \(mode (\d+)\)")


def storage_ensure_layout(dry_run: bool = True) -> dict:
    script = REPO / "scripts" / "storage" / "setup_direct_mounts.sh"
    argv = ["bash", str(script), *(["--dry-run"] if dry_run else [])]
    with jobs.lock_now("res-storage") as free:
        if not free:
            return _refused("storage_ensure_layout", "another layout run is going")
        r = hexec.run(argv, timeout=120)
    text = r.stdout + "\n" + r.stderr
    folders = [{"path": p, "mode": mode} for p, mode in CREATED.findall(text)]
    skipped = re.findall(r"(\w+) is not mounted at", text)
    checks = [
        R.check(f"layout.{t}", "warn", f"{t} isn't mounted: skipped", t)
        for t in skipped
    ]
    if not r.ok:
        checks.append(
            R.check(
                "layout.failed",
                "fail",
                (r.stderr.strip().splitlines() or [f"exit {r.rc}"])[-1][:180],
                "storage",
            )
        )
    verb = "Would create" if dry_run else "Created"
    data = {"dry_run": dry_run, "folders": folders, "skipped_tiers": skipped}
    hints = [DRY_HINT] if dry_run and folders else []
    return R.make(
        checks,
        data,
        hints=hints,
        ok_summary=f"{verb} {len(folders)} folders"
        if folders
        else "Every mounted tier has its folders",
    )


def power_ensure(dry_run: bool = True) -> dict:
    m = config.load()
    current = system.pmset()
    wanted = {r[2]: r for r in sudo_rules(m)}
    # A setting pmset doesn't report doesn't exist on this machine (a VM has no
    # womp): nothing to put back.
    absent = sorted(k for k in wanted if k not in current)
    drift = {
        k: (current[k], r[3])
        for k, r in wanted.items()
        if k in current and current[k] != r[3]
    }
    notes = [
        R.check(f"power.{k}", "ok", f"{k}: not a setting on this machine", "power")
        for k in absent
    ]
    if not drift:
        return R.make(
            notes,
            {"settings": {k: current.get(k) for k in wanted}, "absent": absent},
            summary="Power settings match the 24/7 profile",
        )
    steps = [
        f"sudo -n {' '.join(wanted[k])} (now {now})" for k, (now, _) in drift.items()
    ]
    if dry_run:
        return _plan(
            "power_ensure",
            f"Would set {len(drift)} power settings back",
            steps,
            {"drift": {k: {"now": a, "want": b} for k, (a, b) in drift.items()}},
        )
    with jobs.lock_now("res-power") as free:
        if not free:
            return _refused("power_ensure", "another power_ensure is running")
        problems = []
        for k in drift:
            r = hexec.run(["sudo", "-n", *wanted[k]], timeout=20)
            if not r.ok:
                problems.append((k, (r.stderr or r.stdout).strip()))
    if problems:
        needs_rule = any("password" in msg for _, msg in problems)
        return R.make(
            [
                R.check(f"power.{k}", "fail", msg[:150] or "failed", "power")
                for k, msg in problems
            ],
            {"failed": [k for k, _ in problems]},
            status="fail",
            hints=[
                "Install the sudo rule on the mini: sudo "
                "scripts/core/install_sudoers.sh"
            ]
            if needs_rule
            else [],
        )
    after = system.pmset()
    stuck = [k for k, (_, want) in drift.items() if after.get(k) != want]
    if stuck:  # pmset said yes, but the value didn't change
        return R.make(
            [
                R.check(
                    f"power.{k}",
                    "fail",
                    f"{k} is {after.get(k)} after setting it to {drift[k][1]}",
                    "power",
                )
                for k in stuck
            ],
            {"settings": {k: after.get(k) for k in wanted}},
            status="fail",
        )
    return R.make(
        [],
        {"settings": {k: after.get(k) for k in wanted}, "absent": absent},
        summary=f"Set {len(drift)} power settings back: " + ", ".join(drift),
    )


def logs_collect(since: str = "24h", dry_run: bool = True) -> dict:
    if not re.fullmatch(r"\d{1,4}[mhd]", since):
        return R.error("since is a number and m, h or d, like 24h")
    steps = [
        "The /tmp/homelab-* job logs changed within " + since + " (redacted)",
        "launchctl print for every io.homelab job",
        "system_overview, service_status, storage_status, open incidents, the "
        "last 200 audit rows and 50 jobs",
        "Into one .tgz beside the state database (the last 10 are kept)",
    ]
    if dry_run:
        return _plan(
            "logs_collect", f"Would build a redacted log bundle ({since})", steps
        )
    job = jobs.submit(
        "logs_collect",
        ["python", "-m", "homelab", "bundle", "--since", since],
        tool="logs_collect",
        args={"since": since},
        lock=_lock("logs_collect", {"since": since}),
        timeout=600,
    )
    return _started(job, f"Building the log bundle: job {job['id']}")
