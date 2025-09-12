#!/usr/bin/env bash
set -euo pipefail

echo "$(date): Starting Plex Media Server safely..."

# Check if Plex is already running (test the actual service, not just the process name)
if curl -s http://localhost:32400/identity >/dev/null 2>&1; then
    echo "Plex Media Server already running and accessible"
    exit 0
fi

# Temporarily disable Tailscale serve on port 32400 if active
if sudo tailscale serve status | grep -q ":32400"; then
    echo "Temporarily disabling Tailscale serve for port 32400..."
    sudo tailscale serve --https=32400 off || true
    sleep 2
fi

# Start Plex
echo "Starting Plex Media Server..."
open -a "Plex Media Server"

# Wait for Plex to start
TIMEOUT=30
COUNT=0
while ! curl -s http://localhost:32400 >/dev/null 2>&1 && [[ $COUNT -lt $TIMEOUT ]]; do
    echo "Waiting for Plex to start... ($COUNT/$TIMEOUT)"
    sleep 2
    ((COUNT++))
done

if curl -s http://localhost:32400 >/dev/null 2>&1; then
    echo "✅ Plex Media Server started successfully"
    
    # Re-enable Tailscale HTTPS serving for Plex
    echo "Re-enabling Tailscale HTTPS serving for Plex..."
    if sudo tailscale serve --bg --https=32400 http://localhost:32400 >/dev/null 2>&1; then
        echo "✅ Tailscale HTTPS serving enabled for Plex"
    else
        echo "⚠️  Failed to enable Tailscale HTTPS serving (run manually: sudo tailscale serve --bg --https=32400 http://localhost:32400)"
    fi
else
    echo "❌ Plex Media Server failed to start within $TIMEOUT seconds"
    exit 1
fi

