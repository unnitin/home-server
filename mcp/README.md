# MCP Health Server — Claude Desktop Setup

This MCP server runs on the Mac Mini and exposes all diagnostic tools to Claude Desktop on any device connected via Tailscale.

---

## Mac Mini: Start the Server

```bash
# Install dependencies (first time only)
pip3 install -r mcp/requirements.txt

# Start manually to verify it works
python3 mcp/server.py
# → Running on http://0.0.0.0:8765

# Verify the SSE endpoint responds
curl http://localhost:8765/sse
```

To run as a background service (survives reboots):

```bash
cp launchd/io.homelab.mcp.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/io.homelab.mcp.plist

# Check it loaded
launchctl list | grep io.homelab.mcp
```

---

## MacBook: Connect Claude Desktop

1. Get the Mac Mini's Tailscale hostname:

   ```bash
   # Run on the Mac Mini
   tailscale status | grep mac-mini
   # e.g. nitins-mac-mini.tail-xxxx.ts.net
   ```

2. Edit Claude Desktop config on your MacBook:

   ```
   ~/Library/Application Support/Claude/claude_desktop_config.json
   ```

3. Add the MCP server entry:

   ```json
   {
     "mcpServers": {
       "io.homelab.mcp": {
         "url": "http://nitins-mac-mini.tail-xxxx.ts.net:8765/sse"
       }
     }
   }
   ```

   Replace `nitins-mac-mini.tail-xxxx.ts.net` with your actual Tailscale hostname.

4. Restart Claude Desktop. The tools appear automatically in the tool list.

---

## Verify It's Working

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
- Confirm the server is running: `curl http://localhost:8765/sse` from the Mac Mini
- Confirm Tailscale is connected on both devices: `tailscale status`
- Check server logs: `tail /Volumes/warmstore/logs/mcp/mcp.log`

**Tools time out**
- Most tools have a 60s timeout; `collect_logs` has 120s
- If a diagnostic script hangs, run it directly: `bash diagnostics/check_immich.sh`

**Server won't start**
- Check Python version (requires 3.9+): `python3 --version`
- Check dependencies: `pip3 install -r mcp/requirements.txt`
- Check port isn't already in use: `lsof -i :8765`