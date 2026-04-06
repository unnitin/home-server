import sys
import os

# Ensure the repo root is on the path so `mcp.routing` resolves correctly
# regardless of how the server is launched (launchd, direct python3, etc.)
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE not in sys.path:
    sys.path.insert(0, BASE)

from mcp.server import Server  # noqa: E402  (MCP SDK)
from mcp.server.sse import SseServerTransport  # noqa: E402
from mcp.types import Tool, TextContent  # noqa: E402
from starlette.applications import Starlette  # noqa: E402
from starlette.routing import Route  # noqa: E402
import uvicorn  # noqa: E402

from mcp.routing import TOOL_SCRIPTS, dispatch  # noqa: E402  (our module)

app = Server("io.homelab.mcp")


@app.list_tools()
async def list_tools():
    tools = [
        Tool(name=name, description=_description(name))
        for name in TOOL_SCRIPTS
    ]
    tools.append(Tool(
        name="check_port",
        description="Check a specific host:port",
        inputSchema={
            "type": "object",
            "properties": {
                "host": {"type": "string", "default": "localhost"},
                "port": {"type": "integer"},
            },
            "required": ["port"],
        },
    ))
    return tools


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


@app.call_tool()
async def call_tool(name, arguments):
    out = dispatch(name, arguments)
    return [TextContent(type="text", text=out)]


sse = SseServerTransport("/messages/")


async def handle_sse(request):
    async with sse.connect_sse(request.scope, request.receive, request._send) as (r, w):
        await app.run(r, w, app.create_initialization_options())


starlette_app = Starlette(
    routes=[
        Route("/sse", endpoint=handle_sse),
        Route("/messages/", endpoint=sse.handle_post_message, methods=["POST"]),
    ]
)

if __name__ == "__main__":
    uvicorn.run(starlette_app, host="0.0.0.0", port=8765)