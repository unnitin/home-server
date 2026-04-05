# 🤖 MCP Health Server — Build Specification

**hakuna_mateti · Mac Mini M4 · home-server repo**

> **Purpose:** Add a Model Context Protocol (MCP) server that surfaces all existing `diagnostics/` scripts as Claude-callable tools, runs as a LaunchD service on the Mac Mini, and is accessible from Claude Desktop on any MacBook via Tailscale.
>
> No diagnostic scripts are modified. The MCP is a thin wrapper only.

---

## Architecture

```
MacBook (Claude Desktop)
        │
        │  HTTPS via Tailscale mesh VPN
        ▼
Mac Mini :8765/sse  ←  MCP server (SSE/HTTP, managed by LaunchD)
        │
        │  subprocess calls
        ▼
diagnostics/*.sh  ←  existing scripts, untouched
```

---

## File Inventory

Three new files are added to the repo. All existing diagnostics scripts are unchanged.

| File | Description | Status |
|---|---|---|
| `mcp/server.py` | MCP SSE server, 16 tools | **NEW** |
| `mcp/requirements.txt` | Python deps: mcp, uvicorn, starlette | **NEW** |
| `launchd/io.homelab.mcp.plist` | LaunchD service definition | **NEW** |
| `diagnostics/run_all.sh` | ← no changes | existing |
| `diagnostics/full_summary.sh` | ← no changes | existing |
| `diagnostics/check_prereqs.sh` | ← no changes | existing |
| `diagnostics/check_homebrew.sh` | ← no changes | existing |
| `diagnostics/check_raid_status.sh` | ← no changes | existing |
| `diagnostics/check_storage.sh` | ← no changes | existing |
| `diagnostics/verify_media_paths.sh` | ← no changes | existing |
| `diagnostics/check_colima_docker.sh` | ← no changes | existing |
| `diagnostics/check_docker_services.sh` | ← no changes | existing |
| `diagnostics/check_immich.sh` | ← no changes | existing |
| `diagnostics/check_plex_native.sh` | ← no changes | existing |
| `diagnostics/check_tailscale.sh` | ← no changes | existing |
| `diagnostics/check_reverse_proxy.sh` | ← no changes | existing |
| `diagnostics/network_port_check.sh` | ← no changes | existing |
| `diagnostics/check_launchd.sh` | ← no changes | existing |
| `diagnostics/collect_logs.sh` | ← no changes | existing |

---

## MCP Tool Inventory

Each tool maps 1:1 to an existing diagnostics script. No diagnostic logic lives in the MCP server itself.

| MCP Tool | Script Called | What It Checks |
|---|---|---|
| `run_all_diagnostics` | `diagnostics/run_all.sh` | Full sweep across all components. Primary health check. |
| `quick_summary` | `diagnostics/full_summary.sh` | Fast pass/fail summary. Use before `run_all` when you just want status. |
| `check_prereqs` | `diagnostics/check_prereqs.sh` | Shell version, git, Python, Xcode CLI, file permissions. |
| `check_homebrew` | `diagnostics/check_homebrew.sh` | Homebrew presence, `brew doctor`, write permissions, essential packages. |
| `check_raid` | `diagnostics/check_raid_status.sh` | RAID set status (Online/Degraded/Failed), disk health, mount points, usage warnings. |
| `check_storage` | `diagnostics/check_storage.sh` | Basic storage health across faststore, warmstore, coldstore. |
| `verify_media_paths` | `diagnostics/verify_media_paths.sh` | Mount validation per tier, usage thresholds, write permissions, content detection. |
| `check_colima_docker` | `diagnostics/check_colima_docker.sh` | Colima status, Docker daemon, container runtime, Compose plugin. |
| `check_docker_services` | `diagnostics/check_docker_services.sh` | Immich container health and running state. |
| `check_immich` | `diagnostics/check_immich.sh` | Config file, HTTP availability, database connectivity, API responsiveness. |
| `check_plex` | `diagnostics/check_plex_native.sh` | Process detection, web interface, LaunchAgent status, config, media dirs. |
| `check_tailscale` | `diagnostics/check_tailscale.sh` | Installation, connection status, IP assignment, HTTPS config. |
| `check_reverse_proxy` | `diagnostics/check_reverse_proxy.sh` | Caddy health and routing verification. |
| `check_launchd` | `diagnostics/check_launchd.sh` | All LaunchD jobs: loaded, running, error detection. |
| `collect_logs` | `diagnostics/collect_logs.sh` | Gathers all service logs into timestamped `.tgz`. Timeout: 120s. |
| `check_port` | `diagnostics/network_port_check.sh` | Takes `host` (default: localhost) + `port`. Auto-detects service by port. |

### `check_port` Input Schema

Only tool that takes arguments. All others take no parameters.

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `host` | string | No | Default: `localhost`. Pass Tailscale hostname to test remote. |
| `port` | integer | Yes | Common: `2283` = Immich, `32400` = Plex, `8443` = Caddy |

---

## Implementation

### `mcp/server.py`

```python
import os
import subprocess
from mcp.server import Server
from mcp.server.sse import SseServerTransport
from starlette.applications import Starlette
from starlette.routing import Route
import uvicorn

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAG = os.path.join(BASE, "diagnostics")

app = Server("io.homelab.mcp")

def run(cmd: list[str], timeout=60) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return result.stdout + result.stderr

@app.list_tools()
async def list_tools():
    from mcp.types import Tool
    return [
        Tool(name="run_all_diagnostics",   description="Full health check across all components"),
        Tool(name="quick_summary",         description="Quick summary of server health"),
        Tool(name="check_prereqs",         description="Check prerequisites and dependencies"),
        Tool(name="check_homebrew",        description="Check Homebrew package manager health"),
        Tool(name="check_raid",            description="Check RAID array status and disk health"),
        Tool(name="check_storage",         description="Check storage health across all tiers"),
        Tool(name="verify_media_paths",    description="Verify faststore/warmstore/coldstore mount points"),
        Tool(name="check_colima_docker",   description="Check Colima and Docker runtime health"),
        Tool(name="check_docker_services", description="Check Immich container health"),
        Tool(name="check_immich",          description="Check Immich photo service end-to-end"),
        Tool(name="check_plex",            description="Check Plex Media Server health"),
        Tool(name="check_tailscale",       description="Check Tailscale VPN status"),
        Tool(name="check_reverse_proxy",   description="Check Caddy reverse proxy"),
        Tool(name="check_launchd",         description="Check LaunchD automation services"),
        Tool(name="collect_logs",          description="Collect all logs into a tgz archive"),
        Tool(name="check_port",            description="Check a specific host:port",
             inputSchema={
                 "type": "object",
                 "properties": {
                     "host": {"type": "string", "default": "localhost"},
                     "port": {"type": "integer"}
                 },
                 "required": ["port"]
             }),
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict):
    from mcp.types import TextContent
    match name:
        case "run_all_diagnostics":   out = run(["bash", f"{DIAG}/run_all.sh"])
        case "quick_summary":         out = run(["bash", f"{DIAG}/full_summary.sh"])
        case "check_prereqs":         out = run(["bash", f"{DIAG}/check_prereqs.sh"])
        case "check_homebrew":        out = run(["bash", f"{DIAG}/check_homebrew.sh"])
        case "check_raid":            out = run(["bash", f"{DIAG}/check_raid_status.sh"])
        case "check_storage":         out = run(["bash", f"{DIAG}/check_storage.sh"])
        case "verify_media_paths":    out = run(["bash", f"{DIAG}/verify_media_paths.sh"])
        case "check_colima_docker":   out = run(["bash", f"{DIAG}/check_colima_docker.sh"])
        case "check_docker_services": out = run(["bash", f"{DIAG}/check_docker_services.sh"])
        case "check_immich":          out = run(["bash", f"{DIAG}/check_immich.sh"])
        case "check_plex":            out = run(["bash", f"{DIAG}/check_plex_native.sh"])
        case "check_tailscale":       out = run(["bash", f"{DIAG}/check_tailscale.sh"])
        case "check_reverse_proxy":   out = run(["bash", f"{DIAG}/check_reverse_proxy.sh"])
        case "check_launchd":         out = run(["bash", f"{DIAG}/check_launchd.sh"])
        case "collect_logs":          out = run(["bash", f"{DIAG}/collect_logs.sh"], timeout=120)
        case "check_port":
            host = arguments.get("host", "localhost")
            port = str(arguments.get("port"))
            out = run(["bash", f"{DIAG}/network_port_check.sh", host, port])
        case _:
            out = f"Unknown tool: {name}"
    return [TextContent(type="text", text=out)]

# SSE transport
sse = SseServerTransport("/messages/")

async def handle_sse(request):
    async with sse.connect_sse(request.scope, request.receive, request._send) as (r, w):
        await app.run(r, w, app.create_initialization_options())

starlette_app = Starlette(routes=[
    Route("/sse", endpoint=handle_sse),
    Route("/messages/", endpoint=sse.handle_post_message, methods=["POST"]),
])

if __name__ == "__main__":
    uvicorn.run(starlette_app, host="0.0.0.0", port=8765)
```

### `mcp/requirements.txt`

```
mcp>=1.0.0
uvicorn
starlette
```

### `launchd/io.homelab.mcp.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.homelab.mcp</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>mcp/server.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>PLACEHOLDER — set to the absolute path of this repo at deploy time</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Volumes/warmstore/logs/mcp/mcp.log</string>
    <key>StandardErrorPath</key>
    <string>/Volumes/warmstore/logs/mcp/mcp.error.log</string>
</dict>
</plist>
```

---

## Deployment

Steps 1–6 on the **Mac Mini**. Steps 7–10 on your **MacBook**.

| # | Action |
|---|---|
| 1 | `cd ~/Documents/home-server` |
| 2 | `pip3 install -r mcp/requirements.txt` |
| 3 | Test manually: `python3 mcp/server.py` → should print `Running on http://0.0.0.0:8765` |
| 4 | Edit `launchd/io.homelab.mcp.plist`: replace the `WorkingDirectory` placeholder with the absolute repo path |
| 5 | `cp launchd/io.homelab.mcp.plist ~/Library/LaunchAgents/` |
| 6 | `launchctl load ~/Library/LaunchAgents/io.homelab.mcp.plist` |
| 7 | Verify: `curl http://localhost:8765/sse` → should return SSE stream headers |
| 8 | Get Tailscale hostname: `tailscale status` → note the `hakuna-mateti.tail-xxxx.ts.net` address |
| 9 | On MacBook: edit `~/Library/Application Support/Claude/claude_desktop_config.json` |
| 10 | Add MCP entry pointing to `http://hakuna-mateti.tail-xxxx.ts.net:8765/sse` |
| 11 | Restart Claude Desktop — io.homelab.mcp tools appear in the tool list |

### Claude Desktop Config (MacBook)

Replace the Tailscale hostname with the actual value from `tailscale status` on the Mac Mini.

```json
{
  "mcpServers": {
    "io.homelab.mcp": {
      "url": "http://hakuna-mateti.tail-xxxx.ts.net:8765/sse"
    }
  }
}
```

---

## Testing

Testing splits across two machines:

**Mac Mini (local)**
- `python3 mcp/server.py` starts without errors
- `curl http://localhost:8765/sse` returns SSE headers
- `launchctl list | grep io.homelab.mcp` shows service loaded
- Scripts execute correctly when invoked via the MCP endpoint

**MacBook via Tailscale (end-to-end)**
- Claude Desktop connects to the Tailscale URL
- Tools appear in Claude's tool list
- Natural language prompts invoke the correct tools and return real output

> **Pre-flight check:** Run `python3 --version` on the Mac Mini before installing. The `match/case` syntax in `server.py` requires Python 3.10+. If below 3.10, run `brew install python@3.11` and update the plist path accordingly.

---

## Sample Claude Prompts

| What you say | What happens |
|---|---|
| "Is everything healthy on hakuna?" | `run_all_diagnostics` |
| "Quick status check" | `quick_summary` |
| "Are all my drives mounted?" | `verify_media_paths` + `check_storage` |
| "Plex stopped responding" | `check_plex` → diagnose → advise |
| "Immich feels slow" | `check_immich` + `check_colima_docker` + `check_docker_services` |
| "Is Tailscale connected?" | `check_tailscale` |
| "Is port 2283 responding?" | `check_port` with `port=2283` |
| "Which LaunchD jobs are down?" | `check_launchd` |
| "Collect logs for support" | `collect_logs` |
| "Run full diagnostics and collect logs" | `run_all_diagnostics` + `collect_logs` |

---

## Dependencies

| Dependency | Where | Purpose |
|---|---|---|
| `mcp >= 1.0.0` | pip (Mac Mini) | MCP server SDK — SSE transport, tool registration |
| `uvicorn` | pip (Mac Mini) | ASGI server hosting the SSE endpoint on `:8765` |
| `starlette` | pip (Mac Mini) | ASGI framework used by the SSE transport layer |
| Python 3.10+ | already present | `match` statement syntax required |
| Tailscale | already present | Secure tunnel between MacBook and Mac Mini |
| Claude Desktop | MacBook | Must support remote MCP servers via URL |

---

## Constraints

| Constraint | Detail |
|---|---|
| No script changes | All 16 diagnostics scripts called exactly as-is. Zero logic added on top. |
| Read-only scope | This spec covers observe tools only. Remediation tools (restart, remount etc.) are a separate decision. |
| Tailscale access only | Port 8765 should only accept connections from the Tailscale interface (`utun*`). Firewall rule is a recommended follow-on. |
| No auth layer | Access controlled entirely by Tailscale ACLs. Do not expose port 8765 to the open internet. |
| Timeouts | Most tools: 60s. `collect_logs`: 120s. `run_all_diagnostics` may approach 60s on a degraded system. |
| Python 3.10+ | `match/case` syntax required. Verify before installing. |

---

## Out of Scope

- Remediation tools — `restart_plex`, `restart_colima`, `remount_storage` etc. Separate scope decision.
- Firewall rule restricting `:8765` to Tailscale interface only. Recommended follow-on.
- Authentication layer on the MCP endpoint.
- Proactive alerting (push). This is pull-based — Claude asks when you ask it to.
- Windows or Linux client support.

---

## Acceptance Criteria

- [ ] `pip3 install -r mcp/requirements.txt` completes without errors on the Mac Mini
- [ ] `python3 mcp/server.py` starts and listens on port 8765
- [ ] `curl http://localhost:8765/sse` returns SSE stream headers
- [ ] LaunchD plist loads and service appears in `launchctl list`
- [ ] Claude Desktop on MacBook shows `io.homelab.mcp` in available MCP servers
- [ ] Asking "is Plex running?" triggers `check_plex` and returns script output
- [ ] Asking "run full diagnostics" triggers `run_all_diagnostics` and returns full output
- [ ] `check_port` with `port=2283` calls `network_port_check.sh` with correct arguments
- [ ] MCP service survives a Mac Mini reboot and reconnects automatically (KeepAlive)
- [ ] No existing diagnostics scripts were modified
