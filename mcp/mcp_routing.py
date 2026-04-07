"""
Tool routing table and subprocess executor for the MCP health server.
Kept separate from server.py so it can be imported without the MCP SDK
(useful for testing and for future refactoring).
"""

import os
import subprocess

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAG = os.path.join(BASE, "diagnostics")

TOOL_SCRIPTS = {
    "run_all_diagnostics":   "run_all.sh",
    "quick_summary":         "full_summary.sh",
    "check_prereqs":         "check_prereqs.sh",
    "check_homebrew":        "check_homebrew.sh",
    "check_raid":            "check_raid_status.sh",
    "check_storage":         "check_storage.sh",
    "verify_media_paths":    "verify_media_paths.sh",
    "check_colima_docker":   "check_colima_docker.sh",
    "check_docker_services": "check_docker_services.sh",
    "check_immich":          "check_immich.sh",
    "check_plex":            "check_plex_native.sh",
    "check_tailscale":       "check_tailscale.sh",
    "check_reverse_proxy":   "check_reverse_proxy.sh",
    "check_launchd":         "check_launchd.sh",
    "collect_logs":          "collect_logs.sh",
}

# Tools that need a non-default timeout
TOOL_TIMEOUTS = {
    "collect_logs": 120,
}

DEFAULT_TIMEOUT = 60


def run(cmd, timeout=DEFAULT_TIMEOUT):
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout + result.stderr


def dispatch(name, arguments=None):
    """Route a tool name to the correct script and return its output."""
    if arguments is None:
        arguments = {}

    if name == "check_port":
        host = arguments.get("host", "localhost")
        port = str(arguments["port"])
        return run([
            "bash",
            os.path.join(DIAG, "network_port_check.sh"),
            host,
            port,
        ])

    if name in TOOL_SCRIPTS:
        script = TOOL_SCRIPTS[name]
        timeout = TOOL_TIMEOUTS.get(name, DEFAULT_TIMEOUT)
        return run(["bash", os.path.join(DIAG, script)], timeout=timeout)

    return "Unknown tool: {}".format(name)