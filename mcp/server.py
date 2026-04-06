import os
import subprocess
from mcp.server import Server
from mcp.server.sse import SseServerTransport
from mcp.types import Tool, TextContent
from starlette.applications import Starlette
from starlette.routing import Route
import uvicorn

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAG = os.path.join(BASE, "diagnostics")

app = Server("io.homelab.mcp")


def run(cmd: list[str], timeout: int = 60) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout + result.stderr


@app.list_tools()
async def list_tools():
    return [
        Tool(name="run_all_diagnostics", description="Full health check across all components"),
        Tool(name="quick_summary", description="Quick summary of server health"),
        Tool(name="check_prereqs", description="Check prerequisites and dependencies"),
        Tool(name="check_homebrew", description="Check Homebrew package manager health"),
        Tool(name="check_raid", description="Check RAID array status and disk health"),
        Tool(name="check_storage", description="Check storage health across all tiers"),
        Tool(name="verify_media_paths", description="Verify faststore/warmstore/coldstore mount points"),
        Tool(name="check_colima_docker", description="Check Colima and Docker runtime health"),
        Tool(name="check_docker_services", description="Check Immich container health"),
        Tool(name="check_immich", description="Check Immich photo service end-to-end"),
        Tool(name="check_plex", description="Check Plex Media Server health"),
        Tool(name="check_tailscale", description="Check Tailscale VPN status"),
        Tool(name="check_reverse_proxy", description="Check Caddy reverse proxy"),
        Tool(name="check_launchd", description="Check LaunchD automation services"),
        Tool(name="collect_logs", description="Collect all logs into a tgz archive"),
        Tool(
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
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: dict):
    match name:
        case "run_all_diagnostics":
            out = run(["bash", f"{DIAG}/run_all.sh"])
        case "quick_summary":
            out = run(["bash", f"{DIAG}/full_summary.sh"])
        case "check_prereqs":
            out = run(["bash", f"{DIAG}/check_prereqs.sh"])
        case "check_homebrew":
            out = run(["bash", f"{DIAG}/check_homebrew.sh"])
        case "check_raid":
            out = run(["bash", f"{DIAG}/check_raid_status.sh"])
        case "check_storage":
            out = run(["bash", f"{DIAG}/check_storage.sh"])
        case "verify_media_paths":
            out = run(["bash", f"{DIAG}/verify_media_paths.sh"])
        case "check_colima_docker":
            out = run(["bash", f"{DIAG}/check_colima_docker.sh"])
        case "check_docker_services":
            out = run(["bash", f"{DIAG}/check_docker_services.sh"])
        case "check_immich":
            out = run(["bash", f"{DIAG}/check_immich.sh"])
        case "check_plex":
            out = run(["bash", f"{DIAG}/check_plex_native.sh"])
        case "check_tailscale":
            out = run(["bash", f"{DIAG}/check_tailscale.sh"])
        case "check_reverse_proxy":
            out = run(["bash", f"{DIAG}/check_reverse_proxy.sh"])
        case "check_launchd":
            out = run(["bash", f"{DIAG}/check_launchd.sh"])
        case "collect_logs":
            out = run(["bash", f"{DIAG}/collect_logs.sh"], timeout=120)
        case "check_port":
            host = arguments.get("host", "localhost")
            port = str(arguments["port"])
            out = run(["bash", f"{DIAG}/network_port_check.sh", host, port])
        case _:
            out = f"Unknown tool: {name}"
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