"""MCP health server for the home server.

Listens on 127.0.0.1:18765 only. Tailnet devices reach it at
https://<mini>.<tailnet>.ts.net:8765/mcp through `tailscale serve`
(scripts/infrastructure/apply_tailscale_serve.sh), which also provides TLS.
Nothing on the home LAN can reach it.
"""

import os
import sys
from urllib.parse import urlsplit

import anyio

# Put this directory first so mcp_routing resolves locally while `mcp` still
# resolves to the SDK (this directory is no longer named mcp/, so no shadowing).
SERVER_DIR = os.path.dirname(os.path.abspath(__file__))
if SERVER_DIR not in sys.path:
    sys.path.insert(0, SERVER_DIR)

from mcp.server.fastmcp import FastMCP  # noqa: E402
from mcp.server.transport_security import TransportSecuritySettings  # noqa: E402
from mcp_routing import TOOL_SCRIPTS, dispatch  # noqa: E402

LOOPBACK = {"127.0.0.1", "localhost", "::1"}
HOST = os.environ.get("HOMELAB_MCP_HOST", "127.0.0.1")
PORT = int(os.environ.get("HOMELAB_MCP_PORT", "18765"))


def _host_name(value):
    """'Name:port', '[::1]:port' or 'name' -> lowercase name without the port."""
    value = value.strip().lower()
    if value.startswith("["):
        return value[1 : value.find("]")] if "]" in value else value
    return value.rsplit(":", 1)[0] if value.count(":") == 1 else value


def host_allowed(name, extra=()):
    """DNS-rebinding protection for a loopback-bound server.

    Allows loopback names and tailnet (*.ts.net) names, which is how requests
    relayed by `tailscale serve` may arrive. *.ts.net names never resolve to
    127.0.0.1, so a hostile page can't use one to rebind onto this server. This
    needs no runtime Tailscale lookup: the Mac app's CLI doesn't work from a
    LaunchD-started process. HOMELAB_MCP_ALLOWED_HOSTS adds names (comma-separated).
    """
    return name in LOOPBACK or name.endswith(".ts.net") or name in extra


class HostGuard:
    """ASGI middleware: 421 for a disallowed Host, 403 for a disallowed Origin."""

    def __init__(self, app, extra=()):
        self.app = app
        self.extra = {h.strip().lower() for h in extra if h.strip()}

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            headers = {
                k.decode("latin-1").lower(): v.decode("latin-1")
                for k, v in scope.get("headers", [])
            }
            if not host_allowed(_host_name(headers.get("host", "")), self.extra):
                return await self._reject(send, 421, b"Invalid Host header")
            origin = headers.get("origin")
            if origin and not host_allowed(
                _host_name(urlsplit(origin).netloc), self.extra
            ):
                return await self._reject(send, 403, b"Invalid Origin header")
        await self.app(scope, receive, send)

    @staticmethod
    async def _reject(send, status, body):
        await send(
            {
                "type": "http.response.start",
                "status": status,
                "headers": [(b"content-type", b"text/plain")],
            }
        )
        await send({"type": "http.response.body", "body": body})


def _description(name):
    descriptions = {
        "run_all_diagnostics": "Full health check across all components",
        "quick_summary": "Quick summary of server health",
        "check_prereqs": "Check prerequisites and dependencies",
        "check_homebrew": "Check Homebrew package manager health",
        "check_raid": "Check RAID array status and disk health",
        "check_storage": "Check storage health across all tiers",
        "verify_media_paths": "Verify faststore/warmstore/coldstore mount points",
        "check_colima_docker": "Check Colima and Docker runtime health",
        "check_docker_services": "Check each Immich container is running and healthy",
        "check_immich": "Check Immich photo service end-to-end",
        "check_plex": "Check Plex Media Server health",
        "check_jellyfin": "Check Jellyfin process, port 8096 and health endpoint",
        "check_tailscale": "Check Tailscale VPN status",
        "check_remote_access": "Check tailscale serve mappings and that Funnel is off",
        "check_reverse_proxy": "Deprecated: use check_remote_access",
        "check_launchd": "Check all io.homelab LaunchD jobs and their exit status",
        "collect_logs": "Collect all logs into a tgz archive",
    }
    return descriptions.get(name, name)


def build_server():
    # The SDK's own Host check only knows exact names; HostGuard replaces it.
    server = FastMCP(
        "io.homelab.mcp",
        host=HOST,
        port=PORT,
        transport_security=TransportSecuritySettings(
            enable_dns_rebinding_protection=False
        ),
    )

    # Tools run in a worker thread: a synchronous subprocess call would block the
    # event loop and stall every other request until the diagnostic finished.
    def make_tool(tool_name):
        @server.tool(name=tool_name, description=_description(tool_name))
        async def tool_fn() -> str:
            return await anyio.to_thread.run_sync(dispatch, tool_name)

        return tool_fn

    for name in TOOL_SCRIPTS:
        make_tool(name)

    @server.tool(name="check_port", description="Check a specific host:port")
    async def check_port(port: int, host: str = "localhost") -> str:
        args = {"host": host, "port": port}
        return await anyio.to_thread.run_sync(dispatch, "check_port", args)

    return server


def build_app():
    extra = os.environ.get("HOMELAB_MCP_ALLOWED_HOSTS", "").split(",")
    return HostGuard(build_server().streamable_http_app(), extra)


if __name__ == "__main__":
    import uvicorn

    if HOST not in LOOPBACK and os.environ.get("HOMELAB_MCP_ALLOW_NONLOCAL") != "1":
        sys.exit(
            "Refusing to listen on {}: the MCP server must bind to loopback and be "
            "reached through tailscale serve. Set HOMELAB_MCP_ALLOW_NONLOCAL=1 "
            "to override.".format(HOST)
        )
    print("io.homelab.mcp listening on {}:{}".format(HOST, PORT), flush=True)
    uvicorn.run(build_app(), host=HOST, port=PORT)
