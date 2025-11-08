#!/usr/bin/env bash
# Safely start Jellyfin Media Server
# Handles Tailscale serve configuration

set -euo pipefail

echo "$(date): Starting Jellyfin Media Server safely..."

# Check if Jellyfin is already running
if curl -s http://localhost:8096/health >/dev/null 2>&1; then
    echo "Jellyfin Media Server already running and accessible"
    exit 0
fi

# Verify faststore is mounted
if [[ ! -d "/Volumes/faststore" ]]; then
    echo "❌ ERROR: /Volumes/faststore not mounted"
    exit 1
fi

# Verify Jellyfin is installed
if [[ ! -d "/Applications/Jellyfin.app" ]]; then
    echo "❌ ERROR: Jellyfin.app not found. Run install_jellyfin.sh first"
    exit 1
fi

# Temporarily disable Tailscale serve on port 8096 if active
if tailscale serve status 2>/dev/null | grep -q ":8096"; then
    echo "Temporarily disabling Tailscale serve for port 8096..."
    tailscale serve --https=8096 off || true
    sleep 2
fi

# Start Jellyfin
echo "Starting Jellyfin Media Server..."
open -a "Jellyfin"

# Wait for Jellyfin to start
TIMEOUT=30
COUNT=0
while ! curl -s http://localhost:8096/health >/dev/null 2>&1 && [[ $COUNT -lt $TIMEOUT ]]; do
    echo "Waiting for Jellyfin to start... ($COUNT/$TIMEOUT)"
    sleep 2
    ((COUNT++))
done

if curl -s http://localhost:8096/health >/dev/null 2>&1; then
    echo "✅ Jellyfin Media Server started successfully"
    
    # Re-enable Tailscale HTTPS serving for Jellyfin
    echo "Re-enabling Tailscale HTTPS serving for Jellyfin..."
    if tailscale serve --bg --https=8096 http://localhost:8096 >/dev/null 2>&1; then
        echo "✅ Tailscale HTTPS serving enabled for Jellyfin"
        echo "🌐 Remote access: https://nitins-mac-mini.tailb6b278.ts.net:8096"
    else
        echo "⚠️  Failed to enable Tailscale HTTPS serving (run manually: tailscale serve --bg --https=8096 http://localhost:8096)"
    fi
else
    echo "❌ Jellyfin Media Server failed to start within $TIMEOUT seconds"
    exit 1
fi

