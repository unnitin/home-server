import sys
import os

# Add mcp/ dir to path so mcp_routing resolves without package conflicts
MCP_DIR = os.path.dirname(os.path.abspath(__file__))
if MCP_DIR not in sys.path:
    sys.path.insert(0, MCP_DIR)

from mcp.server.fastmcp import FastMCP  # noqa: E402
from mcp_routing import TOOL_SCRIPTS, dispatch  # noqa: E402

mcp = FastMCP("io.homelab.mcp", host="0.0.0.0", port=8765)


def _description(name):
    descriptions = {
        "run_all_diagnostics":   "Full health check across all components",
        "quick_summary":         "Quick summary of server health",
        "check_prereqs":         "Check prerequisites and dependencies",
        "check_homebrew":        "Check Homebrew package manager health",
        "check_raid":            "Check RAID array status and disk health",
        "check_storage":         "Check storage health across all tiers",
        "verify_media_paths":    "Verify faststore/warmstore/coldstore mount points",
        "check_colima_docker":   "Check Colima and Docker runtime health",
        "check_docker_services": "Check Immich container health",
        "check_immich":          "Check Immich photo service end-to-end",
        "check_plex":            "Check Plex Media Server health",
        "check_tailscale":       "Check Tailscale VPN status",
        "check_reverse_proxy":   "Check Caddy reverse proxy",
        "check_launchd":         "Check LaunchD automation services",
        "collect_logs":          "Collect all logs into a tgz archive",
    }
    return descriptions.get(name, name)


# Register each no-argument tool dynamically
def _make_tool(tool_name):
    desc = _description(tool_name)

    @mcp.tool(name=tool_name, description=desc)
    def tool_fn():
        return dispatch(tool_name)

    return tool_fn


for _name in TOOL_SCRIPTS:
    _make_tool(_name)


@mcp.tool(name="check_port", description="Check a specific host:port")
def check_port(port: int, host: str = "localhost") -> str:
    return dispatch("check_port", {"host": host, "port": port})


if __name__ == "__main__":
    mcp.run(transport="sse")