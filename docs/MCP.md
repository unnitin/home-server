# MCP Health Server

The MCP (Model Context Protocol) server surfaces all diagnostic tools as Claude-callable tools. Ask Claude about your server health in natural language from any device on your Tailscale network.

---

## How It Works

```
MacBook (Claude Desktop)
        │
        │  npx mcp-remote (stdio ↔ HTTP bridge)
        │
        │  HTTP via Tailscale mesh VPN
        ▼
Mac Mini :8765/mcp  ←  MCP server (streamable-http, managed by LaunchD)
        │
        │  subprocess calls
        ▼
diagnostics/*.sh  ←  existing scripts, untouched
```

Claude Desktop connects to the Mac Mini over Tailscale and calls diagnostic scripts on demand. The MCP server is a thin wrapper — all logic lives in the existing `diagnostics/` scripts.

---

## Files

| File | Purpose |
|---|---|
| `mcp/mcp_server.py` | streamable-http server — handles MCP protocol, delegates to mcp_routing.py |
| `mcp/mcp_routing.py` | Tool-to-script mapping and subprocess executor |
| `mcp/requirements.txt` | Python deps: `mcp`, `uvicorn`, `starlette` |
| `launchd/io.homelab.mcp.plist` | LaunchD service — starts on boot, restarts on crash |

---

## Available Tools

| Tool | Script | What It Checks |
|---|---|---|
| `run_all_diagnostics` | `run_all.sh` | Full sweep across all components |
| `quick_summary` | `full_summary.sh` | Fast pass/fail summary |
| `check_prereqs` | `check_prereqs.sh` | Shell, git, Python, Xcode CLI |
| `check_homebrew` | `check_homebrew.sh` | Homebrew health and packages |
| `check_raid` | `check_raid_status.sh` | RAID status, disk health, mounts |
| `check_storage` | `check_storage.sh` | faststore / warmstore / coldstore |
| `verify_media_paths` | `verify_media_paths.sh` | Mount validation, usage thresholds |
| `check_colima_docker` | `check_colima_docker.sh` | Colima, Docker daemon, Compose |
| `check_docker_services` | `check_docker_services.sh` | Immich container health |
| `check_immich` | `check_immich.sh` | Immich HTTP, database, API |
| `check_plex` | `check_plex_native.sh` | Plex process, web interface, LaunchAgent |
| `check_tailscale` | `check_tailscale.sh` | VPN status, IP, HTTPS config |
| `check_reverse_proxy` | `check_reverse_proxy.sh` | Caddy health and routing |
| `check_launchd` | `check_launchd.sh` | All LaunchD jobs status |
| `collect_logs` | `collect_logs.sh` | Gather logs into timestamped `.tgz` |
| `check_port` | `network_port_check.sh` | Test a specific host:port (takes `host`, `port` args) |

---

## Setup

See [mcp/README.md](../mcp/README.md) for full installation and Claude Desktop connection instructions.

Quick version:

```bash
# Mac Mini — install and start
pip3 install -r mcp/requirements.txt
python3 mcp/mcp_server.py

# Mac Mini — install as LaunchD service
cp launchd/io.homelab.mcp.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/io.homelab.mcp.plist
```

Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`) on your MacBook.
Claude Desktop only supports local stdio processes — use `mcp-remote` as a bridge:

```json
{
  "mcpServers": {
    "io.homelab.mcp": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://<tailscale-hostname>:8765/mcp"]
    }
  }
}
```

Node.js must be installed on the MacBook (`brew install node` if missing).

---

## Example Prompts

| Prompt | Tool(s) Called |
|---|---|
| "Is everything healthy on hakuna?" | `run_all_diagnostics` |
| "Quick status check" | `quick_summary` |
| "Are all my drives mounted?" | `verify_media_paths` + `check_storage` |
| "Plex stopped responding" | `check_plex` |
| "Immich feels slow" | `check_immich` + `check_colima_docker` + `check_docker_services` |
| "Is Tailscale connected?" | `check_tailscale` |
| "Is port 2283 responding?" | `check_port` with port=2283 |
| "Which LaunchD jobs are down?" | `check_launchd` |
| "Collect logs for support" | `collect_logs` |

---

## Adding a New Tool

1. Add the diagnostic script to `diagnostics/` following existing conventions
2. Register it in `mcp/mcp_routing.py` — add an entry to `TOOL_SCRIPTS`
3. Add a description in `mcp/mcp_server.py` — add an entry to the `_description()` dict
4. The unit test `test_no_unregistered_diagnostic_scripts` will catch scripts that exist on disk but are not registered

---

## Constraints

- **Read-only** — observe tools only; no restart or remediation actions
- **No auth layer** — access controlled entirely by Tailscale ACLs; do not expose port 8765 to the open internet
- **Timeouts** — most tools: 60s; `collect_logs`: 120s
- **No script changes** — diagnostic scripts are called as-is, zero logic added on top