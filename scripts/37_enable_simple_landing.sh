#!/usr/bin/env bash
# Enable simple landing page with direct service access
# This replaces the complex Caddy reverse proxy with a simple static page

set -euo pipefail

source "$(dirname "$0")/_compose.sh"

banner "Configuring Simple Landing Page with Direct Service Access"

# Get Tailscale hostname for URL display
TAILSCALE_HOSTNAME=$(tailscale status --json | grep '"DNSName"' | cut -d'"' -f4 | sed 's/\.$//' 2>/dev/null || echo "your-device.your-tailnet.ts.net")

echo "Tailscale Hostname: $TAILSCALE_HOSTNAME"

# Stop any existing HTTP server on port 8080
echo "Stopping any existing HTTP server..."
pkill -f "python3 -m http.server 8080" 2>/dev/null || true

# Reset Tailscale serve configuration
echo "Resetting Tailscale serve configuration..."
sudo tailscale serve reset || true

# Start simple HTTP server for landing page
echo "Starting HTTP server for landing page..."
cd "$(dirname "$0")/../web"
nohup python3 -m http.server 8080 --bind 127.0.0.1 > /dev/null 2>&1 &
PYTHON_PID=$!
echo "Started HTTP server (PID: $PYTHON_PID)"

# Wait for HTTP server to start
sleep 2

# Configure Tailscale serve for landing page
echo "Configuring landing page..."
sudo tailscale serve --bg --https=443 http://localhost:8080

# Configure direct service access
echo "Configuring direct Immich access..."
sudo tailscale serve --bg --https=2283 http://localhost:2283

echo "Configuring direct Plex access..."
sudo tailscale serve --bg --https=32400 http://localhost:32400

# Show current configuration
echo ""
echo "Current Tailscale serve configuration:"
sudo tailscale serve status

echo ""
echo "✅ Simple landing page setup complete!"
echo ""
echo "🌐 ACCESSIBLE URLS:"
echo "   📍 Landing Page: https://$TAILSCALE_HOSTNAME"
echo "   📸 Immich (Photos): https://$TAILSCALE_HOSTNAME:2283"
echo "   🎬 Plex (Media): https://$TAILSCALE_HOSTNAME:32400"
echo ""
echo "💡 The landing page provides buttons to access each service directly."
echo "   No complex reverse proxy - just simple, reliable access!"
