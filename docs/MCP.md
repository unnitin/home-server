# MCP Health Server

The MCP (Model Context Protocol) server surfaces all diagnostic tools as Claude-callable tools. Ask Claude about your server health in natural language from any device on your Tailscale network.

---

## How It Works

```
MacBook (Claude Desktop)
        │
        │  npx mcp-remote (stdio ↔ HTTP bridge)
        │
        │  HTTPS via Tailscale: https://<mini>.<tailnet>.ts.net:8765/mcp
        ▼
tailscale serve :8765 (tailnet only, TLS by Tailscale)
        │
        ▼
127.0.0.1:18765/mcp  ←  MCP server (streamable-http, managed by LaunchD; loopback only)
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
| `homelab_mcp/mcp_server.py` | streamable-http server on 127.0.0.1:18765: MCP protocol, Host check, tools run off the event loop |
| `homelab_mcp/mcp_routing.py` | Tool-to-script mapping and subprocess executor (result line, no color codes, timeouts) |
| `homelab_mcp/requirements.txt` | Python deps: `mcp>=1.27,<2`, `uvicorn`, `starlette` |
| `launchd/io.homelab.mcp.plist` | LaunchD service — starts on boot, restarts on crash |

---

## Available Tools

### Structured tools (use these)

They return the result envelope from [`mcp-refactor/02-architecture.md`](mcp-refactor/02-architecture.md#structured-output-contract): `status`, a summary under 200 characters, `data`, the non-OK `checks`, `hints`, `truncated` and `job_id`. Clients get it as MCP `structuredContent`, with an `outputSchema`, and as JSON text. Secrets are redacted, and a result never exceeds 8 KB.

All of them are read-only: they look, and change nothing.

| Tool | Arguments | What it returns |
|---|---|---|
| `system_overview` | `verbose=false` | Every tier (mounted, RAID, used %) and every service's state in one call, the tailnet, and the worst problems (at most 8) with what to call next. Under 2 KB |
| `storage_status` | `tier` (`all` or a tier), `verbose=false` | Per tier: mounted (diskutil decides), RAID set and member status, SMART per member, usage against its thresholds; loose RAID members and unreadable disks |
| `storage_plan_recovery` | `tier` | For a missing or degraded tier: the diagnosis, the pre-checks (is a backup reachable?), and the commands **for a person to run**, each marked read-only, none, or data loss. It never runs anything |
| `service_status` | `service` (`all` or a service), `verbose=false` | Health probe, ports, uptime, containers, LaunchD job and the tiers it needs; state `up`, `degraded`, `down`, `held` or `off` |
| `service_logs` | `service`, `lines=100` (up to 500), `grep`, `container` | The last lines of its LaunchD stdout and stderr, or its containers' logs. Redacted, and marked as data rather than instructions |
| `logs_search` | `query`, `since="24h"`, `sources` (`launchd`, `modules`) | Lines containing the text, in every log changed within `since` (at most 200) |
| `launchd_jobs` | `verbose=false` | Every `io.homelab.*` job: loaded, held, PID, last exit code, runs |
| `docker_containers` | — | Each compose project's containers: state, health, image, restarts, start time |
| `network_check_port` | `port`, `host="localhost"` | Whether a port on the mini accepts connections, and which service owns it. The mini's own ports only |
| `tailscale_status` | — | Connected, DNS name, version, peer counts (never names), and each tailnet mapping against the manifest; Funnel is a failure |
| `power_status` | — | pmset against the manifest's 24/7 profile, what prevents sleep, uptime, macOS version |
| `config_get` | `section` | The manifest, or one section (no secrets) |
| `health_check` | `component` (`all`, `storage`, `raid`, `docker`, `immich`, `plex`, `jellyfin`, `tailscale`, `launchd`, `power`, `network`, `prereqs`, `homebrew`), `verbose=false` | One component's diagnostics: the non-OK checks by default, every check with `verbose=true` |

`health_check` runs the diagnostics in JSON mode (`DIAG_FORMAT=json`, see [`diagnostics/README.md`](../diagnostics/README.md)). The others are the control plane's domains (`homelab/domains/`) over its read-only adapters. The same tools work from a shell: `python3 -m homelab status` and `python3 -m homelab tool NAME KEY=VALUE…`.

### Text tools (deprecated)

These return plain text and stay for existing clients. Each tool's description names the structured tool that replaces it.

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
| `check_docker_services` | `check_docker_services.sh` | Each Immich container running and healthy |
| `check_immich` | `check_immich.sh` | Immich HTTP, database, API |
| `check_plex` | `check_plex_native.sh` | Plex process, web interface, LaunchAgent |
| `check_jellyfin` | `check_jellyfin.sh` | Jellyfin process, port 8096, health endpoint |
| `check_tailscale` | `check_tailscale.sh` | VPN status, IP, HTTPS config |
| `check_remote_access` | `check_remote_access.sh` | `tailscale serve` mappings match `config/tailscale_serve.txt`, Funnel off |
| `check_reverse_proxy` | `check_remote_access.sh` | Deprecated alias of `check_remote_access` (Caddy is no longer used) |
| `check_launchd` | `check_launchd.sh` | Every `io.homelab.*` job: loaded, running, last exit status |
| `collect_logs` | `collect_logs.sh` | Gather logs into timestamped `.tgz` |
| `check_port` | `network_port_check.sh` | Test a specific host:port (takes `host`, `port` args); use `network_check_port` |

---

## Setup

See [homelab_mcp/README.md](../homelab_mcp/README.md) for full installation and Claude Desktop connection instructions.

Quick version:

```bash
# Mac Mini — install and start
/opt/homebrew/bin/python3.11 -m pip install -r homelab_mcp/requirements.txt
/opt/homebrew/bin/python3.11 homelab_mcp/mcp_server.py   # 127.0.0.1:18765

# Mac Mini — install as LaunchD service (renders __REPO__, loads every io.homelab job)
scripts/automation/configure_launchd.sh

# Publish on the tailnet at https://<mini>.<tailnet>.ts.net:8765/mcp
scripts/infrastructure/apply_tailscale_serve.sh
```

Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`) on your MacBook.
Claude Desktop only supports local stdio processes — use `mcp-remote` as a bridge:

```json
{
  "mcpServers": {
    "io.homelab.mcp": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://<mini>.<tailnet>.ts.net:8765/mcp"]
    }
  }
}
```

Node.js must be installed on the MacBook (`brew install node` if missing).

---

## Example Prompts

| Prompt | Tool(s) Called |
|---|---|
| "Is everything healthy on hakuna?" | `system_overview` |
| "Quick status check" | `system_overview` |
| "Are all my drives mounted?" | `storage_status` |
| "warmstore is gone: what do I do?" | `storage_plan_recovery` with tier=warmstore |
| "Plex stopped responding" | `service_status` with service=plex, then `service_logs` |
| "Immich feels slow" | `docker_containers`, then `health_check` with component=immich |
| "Is Tailscale connected?" | `tailscale_status` |
| "Is port 2283 responding?" | `network_check_port` with port=2283 |
| "Which LaunchD jobs are down?" | `launchd_jobs` |
| "Did anything log 'permission denied' today?" | `logs_search` with query="permission denied" |
| "Collect logs for support" | `collect_logs` |

---

## Adding a New Tool

1. Add the diagnostic script to `diagnostics/` following existing conventions
2. Register it in `homelab_mcp/mcp_routing.py` — add an entry to `TOOL_SCRIPTS`
3. Add a description in `homelab_mcp/mcp_server.py` — add an entry to the `_description()` dict
4. The unit test `test_no_unregistered_diagnostic_scripts` will catch scripts that exist on disk but are not registered

---

## Constraints

- **Read-only** — observe tools only; no restart or remediation actions
- **No auth layer yet** (tokens arrive in Phase 3). The server binds to 127.0.0.1 and is reachable only through `tailscale serve`, so only tailnet devices can call it; never enable Funnel on :8765
- **Timeouts** — most tools: 60s; `collect_logs`: 120s
- **No script changes** — diagnostic scripts are called as-is, zero logic added on top