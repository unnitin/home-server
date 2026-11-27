"""Services: each one's LaunchD job, ports, health probe, version and uptime.

A service's health comes from the service itself (its health URL, its port,
its containers), not from its LaunchD job: Colima can be up while its job is
held, and a start script that exits after starting Plex (D32) says nothing
about Plex.
"""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

from homelab import config
from homelab import exec as hexec
from homelab import result as R
from homelab.adapters import diskutil, docker, launchd
from homelab.adapters import http as hhttp


def listener_pid(port: int) -> Optional[int]:
    r = hexec.run(["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-t"], timeout=10)
    pids = [int(p) for p in r.stdout.split() if p.isdigit()]
    return pids[0] if pids else None


def elapsed_s(pid: int) -> Optional[int]:
    """How long a process has run, from `ps -o etime=` ([[dd-]hh:]mm:ss)."""
    r = hexec.run(["ps", "-o", "etime=", "-p", str(pid)])
    m = re.fullmatch(r"(?:(\d+)-)?(?:(\d+):)?(\d+):(\d+)", r.stdout.strip())
    if not m:
        return None
    days, hours, mins, secs = (int(g) if g else 0 for g in m.groups())
    return ((days * 24 + hours) * 60 + mins) * 60 + secs


def probe(url: str, expect: int) -> dict[str, Any]:
    r = hhttp.get(url, timeout=4)
    return {
        "url": url,
        "status": r.status,
        "ok": r.status == expect,
        "ms": r.elapsed_ms,
        **({"error": r.error} if r.error else {}),
    }


def _job_view(j: launchd.Job) -> dict[str, Any]:
    return {
        "label": j.label,
        "loaded": j.loaded,
        "held": j.held,
        "pid": j.pid,
        "last_exit": j.last_exit,
        "runs": j.runs,
    }


def service_report(
    name: str,
    m: config.Manifest,
    job: launchd.Job,
    mounted: dict[str, bool],
) -> tuple[dict[str, Any], list[dict]]:
    svc = m.services[name]
    view: dict[str, Any] = {"kind": svc.kind, "job": _job_view(job)}
    checks: list[dict] = []

    def add(suffix: str, status: str, message: str) -> None:
        checks.append(R.check(f"service.{name}.{suffix}", status, message, name))

    up: Optional[bool] = None  # None: nothing about the service itself to ask
    if svc.health and svc.health.http:
        p = probe(svc.health.http, svc.health.expect)
        view["health"] = p
        up = p["ok"]
        detail = f"HTTP {p['status']}" if p["status"] else p.get("error", "no answer")
        add("health", "ok" if up else "fail", f"{name} health: {detail}")
    elif svc.health and svc.health.cmd:
        r = hexec.run(svc.health.cmd, timeout=10)
        up = r.ok
        view["health"] = {"cmd": " ".join(svc.health.cmd), "ok": up}
        add(
            "health",
            "ok" if up else "fail",
            f"{name}: {' '.join(svc.health.cmd)}"
            + (" answers" if up else f" failed (rc {r.rc})"),
        )

    ports = svc.all_ports()
    if ports:
        listening = {p: listener_pid(p) for p in ports}
        view["ports"] = {str(p): pid is not None for p, pid in listening.items()}
        pid = next((pid for pid in listening.values() if pid), None)
        if pid:
            view["uptime_s"] = elapsed_s(pid)
        if up is None:
            up = all(pid is not None for pid in listening.values())
            add(
                "listening",
                "ok" if up else "fail",
                f"{name} listening on {', '.join(map(str, ports))}"
                if up
                else f"{name} not listening on "
                + ", ".join(str(p) for p, pid in listening.items() if pid is None),
            )

    if svc.kind == "compose" and svc.compose_dir:
        project = docker.compose_ps(
            config.REPO / svc.compose_dir / "docker-compose.yml"
        )
        view["containers"] = [
            {
                "name": c.name,
                "state": c.state,
                "health": c.health,
                "restarts": c.restarts,
            }
            for c in project.containers
        ]
        bad = [c for c in project.containers if not c.ok]
        if not project.runtime:
            add("containers", "fail", f"{name}: docker unavailable ({project.error})")
            up = False
        elif not project.containers:
            add("containers", "fail", f"{name}: no containers")
            up = False
        elif bad:
            add(
                "containers",
                "fail",
                f"{name}: "
                + ", ".join(f"{c.name} {c.state} {c.health}".strip() for c in bad),
            )
            up = False

    # The job itself: held on purpose, failing, or missing.
    if job.held:
        status = "ok" if up else "warn"
        add(
            "job",
            status,
            f"{job.label} is held (launchctl disable)"
            + ("; the service runs anyway" if up else ""),
        )
    elif not job.loaded:
        status = "ok" if svc.optional else ("warn" if up else "fail")
        add(
            "job",
            status,
            f"{job.label} is not loaded" + (" (optional)" if svc.optional else ""),
        )
    elif job.failed:
        add("job", "warn", f"{job.label} last exited {job.last_exit}")
    elif up is None:
        up = job.loaded and not job.failed

    deps = [d for d in svc.depends_on if d in m.storage.tiers and not mounted.get(d)]
    if deps and up:
        add("depends", "warn", f"{name} is up but {', '.join(deps)} is not mounted")
    view["depends_on"] = {
        d: (mounted.get(d) if d in m.storage.tiers else None) for d in svc.depends_on
    }

    if job.held and up is not True:
        state = "held"
    elif svc.optional and not job.loaded and up is None:
        state = "off"
    elif up is None:
        state = "unknown"
    elif not up:
        state = "down"
    elif deps or any(c["status"] != "ok" for c in checks):
        state = "degraded"
    else:
        state = "up"
    view["state"] = state
    return view, checks


def _mounted(m: config.Manifest) -> dict[str, bool]:
    return {n: diskutil.volume(t.mount) is not None for n, t in m.storage.tiers.items()}


def status(service: str = "all", verbose: bool = False) -> dict:
    m = config.load()
    names = list(m.boot_order) if service == "all" else [service]
    if any(n not in m.services for n in names):
        return R.error(
            f"unknown service {service!r}; use one of all, {', '.join(m.boot_order)}"
        )
    jobs = {j.label: j for j in launchd.jobs([m.services[n].launchd for n in names])}
    mounted = _mounted(m)
    with ThreadPoolExecutor(max_workers=min(8, len(names))) as pool:
        reports = list(
            pool.map(
                lambda n: service_report(n, m, jobs[m.services[n].launchd], mounted),
                names,
            )
        )
    services, checks = {}, []
    for name, (view, svc_checks) in zip(names, reports):
        services[name] = view
        checks += svc_checks
    states = [v["state"] for v in services.values()]
    hints = [
        f"service_logs(service='{n}')"
        for n, v in services.items()
        if v["state"] == "down"
    ][:3]
    return R.make(
        checks,
        (
            {"services": services}
            if len(names) > 1
            else {"service": names[0], **services[names[0]]}
        ),
        ok_summary=(
            f"All {len(names)} services up"
            if len(names) > 1
            else f"{names[0]} is {states[0]}"
        ),
        hints=hints,
        verbose=verbose,
    )


def launchd_jobs(verbose: bool = False) -> dict:
    m = config.load()
    labels = [m.services[n].launchd for n in m.boot_order]
    jobs = launchd.jobs(labels)
    checks = []
    for name, j in zip(m.boot_order, jobs):
        optional = m.services[name].optional
        if j.held:
            checks.append(
                R.check(f"launchd.{name}", "warn", f"{j.label} held", "launchd")
            )
        elif not j.loaded:
            checks.append(
                R.check(
                    f"launchd.{name}",
                    "ok" if optional else "fail",
                    f"{j.label} not loaded" + (" (optional)" if optional else ""),
                    "launchd",
                )
            )
        elif j.failed:
            checks.append(
                R.check(
                    f"launchd.{name}",
                    "warn",
                    f"{j.label} last exited {j.last_exit}",
                    "launchd",
                )
            )
        else:
            checks.append(R.check(f"launchd.{name}", "ok", f"{j.label} ok", "launchd"))
    data = {
        "jobs": [
            _job_view(j) | {"service": n, "state": j.state, "keepalive": j.keepalive}
            for n, j in zip(m.boot_order, jobs)
        ]
    }
    loaded = sum(j.loaded for j in jobs)
    return R.make(
        checks,
        data,
        ok_summary=f"{loaded} of {len(jobs)} jobs loaded, none failing",
        verbose=verbose,
    )


def docker_containers() -> dict:
    m = config.load()
    checks, projects = [], {}
    for name, svc in m.services.items():
        if svc.kind != "compose" or not svc.compose_dir:
            continue
        p = docker.compose_ps(config.REPO / svc.compose_dir / "docker-compose.yml")
        projects[name] = {
            "runtime": p.runtime,
            "error": p.error or None,
            "containers": [
                {
                    "name": c.name,
                    "service": c.service,
                    "state": c.state,
                    "health": c.health or None,
                    "image": c.image,
                    "status": c.status,
                    "restarts": c.restarts,
                    "started": c.started,
                }
                for c in p.containers
            ],
        }
        if not p.runtime:
            checks.append(
                R.check(f"docker.{name}", "fail", f"{name}: {p.error}", "docker")
            )
        for c in p.containers:
            status = "ok" if c.ok else "fail"
            if c.ok and c.restarts:
                status = "warn"
            checks.append(
                R.check(
                    f"docker.{c.name}",
                    status,
                    f"{c.name} {c.status}"
                    + (f", {c.restarts} restarts" if c.restarts else ""),
                    "docker",
                )
            )
    n = sum(len(p["containers"]) for p in projects.values())
    return R.make(
        checks, {"projects": projects}, ok_summary=f"All {n} containers running"
    )
