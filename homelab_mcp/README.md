# MCP Health Server: Setup

The MCP server runs on the Mac mini and exposes the diagnostic tools to MCP clients (Claude Desktop and others) on any device in your tailnet.

```
tailnet device ──https──► tailscale serve :8765 ──► 127.0.0.1:18765 (this server)
```

- The server listens on **127.0.0.1:18765 only**. Nothing on the home LAN can reach it, and it refuses to start on a non-loopback address.
- Tailnet devices reach it at **`https://<mini>.<tailnet>.ts.net:8765/mcp`** through `tailscale serve` (Serve, never Funnel, so not the internet). Tailscale provides and renews the TLS certificate; no cert files to manage.
- The mapping comes from `config/tailscale_serve.txt`, applied by `scripts/infrastructure/apply_tailscale_serve.sh`.

---

## Mac mini: install and run

```bash
# Dependencies (mcp is pinned below 2.x: 2.x renamed the server API)
/opt/homebrew/bin/python3.11 -m pip install -r homelab_mcp/requirements.txt

# Try it in the foreground
/opt/homebrew/bin/python3.11 homelab_mcp/mcp_server.py
# → io.homelab.mcp listening on 127.0.0.1:18765

# As a LaunchD job (starts at login, restarts on crash). This renders and loads
# every io.homelab job, io.homelab.mcp included:
scripts/automation/configure_launchd.sh

# Publish it to the tailnet (adds the :8765 mapping once the server answers)
scripts/infrastructure/apply_tailscale_serve.sh

# Logs
tail -f /tmp/homelab-mcp.out /tmp/homelab-mcp.err
```

Environment variables (set in `launchd/io.homelab.mcp.plist`):

| Variable | Default | Purpose |
|---|---|---|
| `HOMELAB_MCP_HOST` | `127.0.0.1` | Bind address. Loopback only unless `HOMELAB_MCP_ALLOW_NONLOCAL=1` |
| `HOMELAB_MCP_PORT` | `18765` | Bind port (tailnet clients use 8765 via serve) |
| `HOMELAB_MCP_ALLOWED_HOSTS` | (none) | Extra `Host` names to accept besides loopback and `*.ts.net` |
| `PATH` | Homebrew first | LaunchD's default PATH hides `docker`, `colima` and other Homebrew tools |

---

## Tokens

Every request needs a bearer token. Make one per client on the mini; it's printed once, and only its hash is kept in the state database:

```bash
python3 -m homelab token create macbook-claude --scope ops   # T0 + T1 (safe actions)
python3 -m homelab token create dashboard --scope observe    # read-only
python3 -m homelab token create small-model --scope observe --toolset core
python3 -m homelab token list
python3 -m homelab token revoke macbook-claude               # refused from its next request
```

Scopes (`config/policy.yaml`): `observe` sees the read-only (T0) tools, `ops` adds the safe actions (T1), `admin` adds changes that need approval (T2, Phase 5), `curator` sees the curation tools only. A client only sees, and can only call, what its token allows. Every call is in the audit log: `python3 -m homelab audit`, or the `audit_recent` tool.

---

## MacBook: connect Claude Desktop

Claude Desktop launches local stdio processes, so use `mcp-remote` as a stdio-to-HTTP bridge (needs Node: `brew install node`). It sends the token as a header.

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "io.homelab.mcp": {
      "command": "npx",
      "args": [
        "-y", "mcp-remote", "https://<mini>.<tailnet>.ts.net:8765/mcp",
        "--header", "Authorization:${HOMELAB_AUTH}"
      ],
      "env": { "HOMELAB_AUTH": "Bearer hlk_..." }
    }
  }
}
```

Restart Claude Desktop, then try "Is everything healthy on the server?" (`system_overview`).

Claude Code: `claude mcp add --transport http homelab https://<mini>.<tailnet>.ts.net:8765/mcp --header "Authorization: Bearer hlk_..."`.

---

## Troubleshooting

**Clients can't connect**
- On the mini: `bash diagnostics/check_remote_access.sh` shows whether the :8765 mapping exists and whether the server answers.
- `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:18765/mcp` on the mini should print `401` (server up, wants a token).
- From the MacBook: `curl -i https://<mini>.<tailnet>.ts.net:8765/mcp`.
- Both devices connected: `tailscale status`.

**HTTP 401**: no token, or one that's unknown, revoked or expired. `homelab token list` shows which exist.

**HTTP 421 "Invalid Host header"**: the request's Host isn't loopback or a `*.ts.net` name. Add it to `HOMELAB_MCP_ALLOWED_HOSTS`.

**Tools report Docker or Colima missing**: the server was started without Homebrew on PATH. Use the LaunchD job, or export `PATH=/opt/homebrew/bin:$PATH`.

**Server won't start**
- `ImportError: ... fastmcp`: mcp 2.x is installed. `pip install 'mcp>=1.27,<2'`.
- `Refusing to listen on ...`: `HOMELAB_MCP_HOST` isn't loopback. That's intentional.
- Port in use: `lsof -nP -iTCP:18765 -sTCP:LISTEN`.

**Tool results**: each starts with `Result: OK (exit 0)`, `Result: FAIL (exit N)` or `Result: TIMEOUT after Ns`. Most tools time out at 60s, `collect_logs` at 120s.
