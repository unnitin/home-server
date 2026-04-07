# MCP Health Server — Claude Desktop Setup

This MCP server runs on the Mac Mini and exposes all diagnostic tools to Claude Desktop on any device connected via Tailscale.

---

## Mac Mini: TLS Certificate

The server uses a Tailscale-issued TLS cert stored outside the repo in `~/.config/tailscale/`. Generate once:

```bash
mkdir -p ~/.config/tailscale
cd ~/.config/tailscale
tailscale cert $(tailscale status --json | python3 -c "import sys,json; print(json.load(sys.stdin)['Self']['DNSName'].rstrip('.'))")
```

Certs expire periodically. Regenerate with the same command — Tailscale will renew automatically if `tailscaled` is running.

---

## Mac Mini: Start the Server

```bash
# Install dependencies (first time only)
pip3 install -r mcp/requirements.txt

# Start manually to verify it works
python3 mcp/mcp_server.py
# → Running on http://0.0.0.0:8765

# Verify the endpoint responds (405 = server is up, expects POST)
curl -i http://localhost:8765/mcp
```

To run as a background service (survives reboots):

```bash
cp launchd/io.homelab.mcp.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/io.homelab.mcp.plist

# Check it loaded
launchctl list | grep io.homelab.mcp

# Tail logs
tail -f /tmp/io.homelab.mcp.log
```

---

## MacBook: Connect Claude Desktop

Claude Desktop only launches local stdio processes — it cannot connect to a remote HTTP server directly. Use `mcp-remote` (an npm package) as a stdio-to-HTTP bridge.

### Prerequisites

Node.js must be installed on the MacBook:

```bash
# Check if node is installed
node --version

# Install via Homebrew if missing
brew install node
```

### Config

Edit Claude Desktop config on your MacBook:

```
~/Library/Application Support/Claude/claude_desktop_config.json
```

Add the MCP server entry using `mcp-remote`:

```json
{
  "mcpServers": {
    "io.homelab.mcp": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "http://your-mac-mini.tailXXXXXX.ts.net:8765/mcp"]
    }
  }
}
```

The `-y` flag tells npx to auto-install `mcp-remote` if not cached. Restart Claude Desktop after saving.

### Verify

In Claude Desktop, try:

> "Is everything healthy on hakuna?"

Claude will call `run_all_diagnostics` and return real output from the Mac Mini.

Other prompts that work:
- "Quick status check" → `quick_summary`
- "Is Immich up?" → `check_immich`
- "Are all drives mounted?" → `check_storage` + `verify_media_paths`
- "Is port 2283 open?" → `check_port` with port=2283

---

## Troubleshooting

**Claude Desktop doesn't show the tools**
- Confirm Node is installed on MacBook: `node --version`
- Confirm the server is reachable from MacBook: `curl -i http://your-mac-mini.tailXXXXXX.ts.net:8765/mcp`
- Confirm Tailscale is connected on both devices: `tailscale status`
- Check server logs on Mac Mini: `tail -f /tmp/io.homelab.mcp.log`
- Check Claude Desktop logs (MacBook): `tail -f ~/Library/Logs/Claude/mcp-server-io.homelab.mcp.log`

**"Some MCP servers could not be loaded" error**
- This means Claude Desktop tried to spawn the process but it failed
- Run manually to see the error: `npx -y mcp-remote http://your-mac-mini.tailXXXXXX.ts.net:8765/mcp`
- If network is unreachable: check Tailscale is running on both machines

**Tools time out**
- Most tools have a 60s timeout; `collect_logs` has 120s
- If a diagnostic script hangs, run it directly: `bash diagnostics/check_immich.sh`

**Server won't start on Mac Mini**
- Check Python version (requires 3.9+): `python3 --version`
- Check dependencies: `pip3 install -r mcp/requirements.txt`
- Check port isn't already in use: `lsof -i :8765`
