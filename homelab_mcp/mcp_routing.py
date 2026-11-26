"""
Tool routing table and subprocess executor for the MCP health server.
Kept separate from mcp_server.py so it can be imported without the MCP SDK
(useful for testing and for future refactoring).
"""

import os
import re
import subprocess

# LaunchD starts the server with PATH=/usr/bin:/bin:/usr/sbin:/sbin, which hides
# docker, colima and other Homebrew tools from the diagnostics.
EXTRA_PATH = ["/opt/homebrew/bin", "/usr/local/bin"]
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAG = os.path.join(BASE, "diagnostics")

TOOL_SCRIPTS = {
    "run_all_diagnostics": "run_all.sh",
    "quick_summary": "full_summary.sh",
    "check_prereqs": "check_prereqs.sh",
    "check_homebrew": "check_homebrew.sh",
    "check_raid": "check_raid_status.sh",
    "check_storage": "check_storage.sh",
    "verify_media_paths": "verify_media_paths.sh",
    "check_colima_docker": "check_colima_docker.sh",
    "check_docker_services": "check_docker_services.sh",
    "check_immich": "check_immich.sh",
    "check_plex": "check_plex_native.sh",
    "check_jellyfin": "check_jellyfin.sh",
    "check_tailscale": "check_tailscale.sh",
    "check_remote_access": "check_remote_access.sh",
    # Deprecated alias: Caddy is gone, remote access is tailscale serve
    "check_reverse_proxy": "check_remote_access.sh",
    "check_launchd": "check_launchd.sh",
    "collect_logs": "collect_logs.sh",
}

# Tools that need a non-default timeout
TOOL_TIMEOUTS = {
    "collect_logs": 120,
}

DEFAULT_TIMEOUT = 60


def _env():
    env = dict(os.environ)
    path = env.get("PATH", "/usr/bin:/bin:/usr/sbin:/sbin").split(":")
    env["PATH"] = ":".join(path + [p for p in EXTRA_PATH if p not in path])
    env["NO_COLOR"] = "1"
    return env


def _text(value):
    if value is None:
        return ""
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    return ANSI_ESCAPE.sub("", value)


def run(cmd, timeout=DEFAULT_TIMEOUT):
    """Run a diagnostic and return its output, prefixed with an explicit result line.

    The first line is "Result: OK (exit 0)", "Result: FAIL (exit N)",
    "Result: TIMEOUT after Ns" or "Result: ERROR (...)", so a model never has to
    guess pass/fail from the text. Output has no terminal color codes.
    """
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, env=_env()
        )
    except subprocess.TimeoutExpired as exc:
        partial = _text(exc.stdout) + _text(exc.stderr)
        return "Result: TIMEOUT after {}s (partial output below)\n{}".format(
            timeout, partial
        )
    except OSError as exc:
        return "Result: ERROR (could not run {}: {})\n".format(cmd[0], exc)

    status = "OK" if result.returncode == 0 else "FAIL"
    output = _text(result.stdout) + _text(result.stderr)
    return "Result: {} (exit {})\n{}".format(status, result.returncode, output)


def dispatch(name, arguments=None):
    """Route a tool name to the correct script and return its output."""
    if arguments is None:
        arguments = {}

    if name == "check_port":
        host = arguments.get("host", "localhost")
        port = str(arguments["port"])
        return run(
            [
                "bash",
                os.path.join(DIAG, "network_port_check.sh"),
                host,
                port,
            ]
        )

    if name in TOOL_SCRIPTS:
        script = TOOL_SCRIPTS[name]
        timeout = TOOL_TIMEOUTS.get(name, DEFAULT_TIMEOUT)
        return run(["bash", os.path.join(DIAG, script)], timeout=timeout)

    return "Unknown tool: {}".format(name)


# --- Structured tools (Phase 1): health_check and system_overview -------------
# They run diagnostics with DIAG_FORMAT=json and return the result envelope
# (envelope.py) instead of text. The tools above stay for existing clients.

# health_check components (03-tool-catalog.md) and the diagnostics behind each:
# (script, args). Ports move to config/homelab.yaml with the manifest.
COMPONENT_SCRIPTS = {
    "all": [("run_all.sh", ())],
    "storage": [("check_storage.sh", ()), ("verify_media_paths.sh", ())],
    "raid": [("check_raid_status.sh", ())],
    "docker": [("check_colima_docker.sh", ()), ("check_docker_services.sh", ())],
    "immich": [("check_immich.sh", ())],
    "plex": [("check_plex_native.sh", ())],
    "jellyfin": [("check_jellyfin.sh", ())],
    "tailscale": [("check_tailscale.sh", ()), ("check_remote_access.sh", ())],
    "launchd": [("check_launchd.sh", ())],
    "power": [("check_power_settings.sh", ())],
    "network": [
        ("network_port_check.sh", ("localhost", "2283")),
        ("network_port_check.sh", ("localhost", "32400")),
        ("network_port_check.sh", ("localhost", "8096")),
    ],
    "prereqs": [("check_prereqs.sh", ())],
    "homebrew": [("check_homebrew.sh", ())],
}
COMPONENTS = list(COMPONENT_SCRIPTS)
COMPONENT_TIMEOUTS = {"all": 300}

# What system_overview covers: every service and storage, in one call.
OVERVIEW_COMPONENTS = [
    "storage",
    "raid",
    "docker",
    "immich",
    "plex",
    "jellyfin",
    "tailscale",
    "launchd",
    "power",
]
OVERVIEW_MAX_CHECKS = 10  # keeps the overview small; health_check has the rest
TIERS = {"faststore": "faststore", "warmstore": "warmstore", "coldstore": "Archive"}


def run_json(script, args=(), timeout=DEFAULT_TIMEOUT):
    """Run one diagnostic in JSON mode: (records, errors)."""
    import envelope  # local import: envelope.py sits next to this file

    env = _env()
    env["DIAG_FORMAT"] = "json"
    env.pop("DIAG_JSON_FD_READY", None)
    cmd = ["bash", os.path.join(DIAG, script), *args]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, env=env
        )
    except subprocess.TimeoutExpired as exc:
        records, _ = envelope.parse_stream(_text(exc.stdout))
        return records, ["{} timed out after {}s".format(script, timeout)]
    except OSError as exc:
        return [], ["could not run {}: {}".format(script, exc)]
    records, _bad = envelope.parse_stream(result.stdout)
    errors = []
    if not any(r.get("type") == "summary" for r in records):
        errors.append(
            "{} printed no summary (exit {})".format(script, result.returncode)
        )
    return records, errors


def _run_many(jobs, timeout):
    """Run (script, args) jobs in parallel; returns (records, errors) in order."""
    from concurrent.futures import ThreadPoolExecutor

    with ThreadPoolExecutor(max_workers=max(1, min(8, len(jobs)))) as pool:
        results = list(pool.map(lambda job: run_json(job[0], job[1], timeout), jobs))
    records, errors = [], []
    for recs, errs in results:
        records.extend(recs)
        errors.extend(errs)
    return records, errors


def health_check(component="all", verbose=False):
    """Run the diagnostics for one component and return the envelope."""
    import envelope

    if component not in COMPONENT_SCRIPTS:
        raise ValueError(
            "unknown component {!r}; use one of {}".format(
                component, ", ".join(COMPONENTS)
            )
        )
    timeout = COMPONENT_TIMEOUTS.get(component, DEFAULT_TIMEOUT)
    records, errors = _run_many(COMPONENT_SCRIPTS[component], timeout)
    return envelope.build(
        records, verbose=verbose, errors=errors, data={"component": component}
    )


def tier_usage(volumes_root=None):
    """Each storage tier: mounted, and used % when it is."""
    import shutil

    root = volumes_root or os.environ.get("HOMELAB_VOLUMES_ROOT", "/Volumes")
    tiers = {}
    for name, folder in TIERS.items():
        path = os.path.join(root, folder)
        # ismount, not isdir: an empty mount-point folder is not a volume (D22)
        mounted = os.path.ismount(path)
        used = None
        if mounted:
            usage = shutil.disk_usage(path)
            used = round(100 * usage.used / usage.total) if usage.total else None
        tiers[name] = {"mounted": mounted, "used_pct": used}
    return tiers


def tier_records(tiers):
    """Diagnostic-style records for tier mounts: faststore and warmstore must be
    mounted (fail); coldstore is an archive no service needs (warn)."""
    records, counts = [], {"ok": 0, "warn": 0, "fail": 0}
    for name, tier in tiers.items():
        if tier["mounted"]:
            status = "ok"
            message = "{} mounted, {}% used".format(name, tier["used_pct"])
        else:
            status = "warn" if name == "coldstore" else "fail"
            message = "{} is not mounted".format(name)
        counts[status] += 1
        records.append(
            {
                "type": "check",
                "id": "tiers.mount.{}".format(name),
                "component": "tiers",
                "status": status,
                "message": message,
            }
        )
    worst = "fail" if counts["fail"] else "warn" if counts["warn"] else "ok"
    records.append(
        {
            "type": "summary",
            "component": "tiers",
            "status": worst,
            "passed": counts["ok"],
            "warnings": counts["warn"],
            "failures": counts["fail"],
            "exit_code": 0,
        }
    )
    return records


def system_overview(verbose=False):
    """One call: every service's and tier's state, small enough for any model."""
    import envelope

    jobs = [job for comp in OVERVIEW_COMPONENTS for job in COMPONENT_SCRIPTS[comp]]
    records, errors = _run_many(jobs, DEFAULT_TIMEOUT)
    tiers = tier_usage()
    records.extend(tier_records(tiers))
    result = envelope.build(
        records, verbose=verbose, errors=errors, data={"tiers": tiers}
    )
    if not verbose and len(result["checks"]) > OVERVIEW_MAX_CHECKS:
        result["checks"] = result["checks"][:OVERVIEW_MAX_CHECKS]
        result["truncated"] = True
        result["hints"].append("health_check(component=...) lists every check")
    return result
