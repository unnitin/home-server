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
MANIFEST_ENV = os.path.join(BASE, "config", "homelab.env")


def read_manifest_env(path=MANIFEST_ENV):
    """The manifest's values (config/homelab.env, generated from homelab.yaml).

    The standard library only: the Python LaunchD runs this with has pydantic
    but no PyYAML, so the YAML itself is never read here. Lines are
    KEY="value", with backslash, double quote, dollar and backtick escaped by a
    backslash; a leading $HOME/ expands to the home folder.
    """
    values = {}
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return values
    for line in lines:
        m = re.match(r'^(HOMELAB_[A-Z0-9_]+)="(.*)"$', line)
        if not m:
            continue
        value = re.sub(r"\\([\\\"$`])", r"\1", m.group(2))
        if m.group(2).startswith("$HOME/"):
            value = os.path.join(os.path.expanduser("~"), value[len("$HOME/") :])
        values[m.group(1)] = value
    return values


MANIFEST = read_manifest_env()


def _port(service, default):
    """A service's first port from the manifest, or the default."""
    ports = MANIFEST.get("HOMELAB_SVC_{}_PORTS".format(service.upper()), "")
    return ports.split()[0] if ports.split() else default


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


# --- health_check (Phase 1) ----------------------------------------------------
# It runs diagnostics with DIAG_FORMAT=json and returns the result envelope
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
        ("network_port_check.sh", ("localhost", _port("immich", "2283"))),
        ("network_port_check.sh", ("localhost", _port("plex", "32400"))),
        ("network_port_check.sh", ("localhost", _port("jellyfin", "8096"))),
    ],
    "prereqs": [("check_prereqs.sh", ())],
    "homebrew": [("check_homebrew.sh", ())],
}
COMPONENTS = list(COMPONENT_SCRIPTS)
COMPONENT_TIMEOUTS = {"all": 300}


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


# system_overview is homelab/domains/health.py: built on the adapters, not the
# diagnostics (Phase 2).
