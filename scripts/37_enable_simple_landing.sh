#!/usr/bin/env bash
# Enable simple landing page with direct service access
# Enhanced for Option C: Graceful permission handling with fallback guidance

set -euo pipefail

source "$(dirname "$0")/_compose.sh"

# Support setup mode (skip service waiting) vs automation mode
SETUP_MODE=false
if [[ "${1:-}" == "--setup-mode" ]]; then
    SETUP_MODE=true
    shift
fi

banner "Configuring Simple Landing Page with Direct Service Access"

# Get Tailscale hostname for URL display
TAILSCALE_HOSTNAME=$(tailscale status --json | grep '"DNSName"' | cut -d'"' -f4 | sed 's/\.$//' 2>/dev/null || echo "your-device.your-tailnet.ts.net")

echo "Tailscale Hostname: $TAILSCALE_HOSTNAME"

# Stop any existing HTTP server on port 8080
echo "Stopping any existing HTTP server..."
pkill -f "python3 -m http.server 8080" 2>/dev/null || true

# Start simple HTTP server for landing page (always works)
echo "Starting HTTP server for landing page..."
cd "$(dirname "$0")/../web"
nohup python3 -m http.server 8080 --bind 127.0.0.1 > /dev/null 2>&1 &
PYTHON_PID=$!
echo "✅ Started HTTP server (PID: $PYTHON_PID)"

# Wait for HTTP server to start
sleep 2

# Graceful Tailscale HTTPS configuration
echo ""
echo "🔧 Configuring Tailscale HTTPS serving..."

# Track configuration success
TAILSCALE_SUCCESS=true
MANUAL_COMMANDS=()

# Reset Tailscale serve configuration
if sudo tailscale serve reset >/dev/null 2>&1; then
    echo "  ✅ Reset existing Tailscale configuration"
else
    echo "  ⚠️  Could not reset Tailscale configuration (continuing...)"
fi

# Configure landing page HTTPS
if sudo tailscale serve --bg --https=443 http://localhost:8080 >/dev/null 2>&1; then
    echo "  ✅ Landing page HTTPS configured"
else
    echo "  ⚠️  Landing page HTTPS failed (permission denied)"
    TAILSCALE_SUCCESS=false
    MANUAL_COMMANDS+=("sudo tailscale serve --bg --https=443 http://localhost:8080")
fi

# Wait for services if not in setup mode
if ! $SETUP_MODE; then
    echo "  🔍 Waiting for services to be available..."
    
    # Wait for Immich (with timeout)
    IMMICH_READY=false
    for i in {1..30}; do
        if curl -s http://localhost:2283 >/dev/null 2>&1; then
            IMMICH_READY=true
            break
        fi
        sleep 2
    done
    
    # Wait for Plex (with timeout)
    PLEX_READY=false
    for i in {1..30}; do
        if curl -s http://localhost:32400 >/dev/null 2>&1; then
            PLEX_READY=true
            break
        fi
        sleep 2
    done
else
    # In setup mode, assume services will be available
    IMMICH_READY=true
    PLEX_READY=true
fi

# Configure Immich HTTPS if available
if $IMMICH_READY; then
    if sudo tailscale serve --bg --https=2283 http://localhost:2283 >/dev/null 2>&1; then
        echo "  ✅ Immich HTTPS configured"
    else
        echo "  ⚠️  Immich HTTPS failed (permission denied)"
        TAILSCALE_SUCCESS=false
        MANUAL_COMMANDS+=("sudo tailscale serve --bg --https=2283 http://localhost:2283")
    fi
else
    echo "  ⚠️  Immich not available yet, skipping HTTPS setup"
    MANUAL_COMMANDS+=("sudo tailscale serve --bg --https=2283 http://localhost:2283")
fi

# Configure Plex HTTPS if available
if $PLEX_READY; then
    if sudo tailscale serve --bg --https=32400 http://localhost:32400 >/dev/null 2>&1; then
        echo "  ✅ Plex HTTPS configured"
    else
        echo "  ⚠️  Plex HTTPS failed (permission denied)"
        TAILSCALE_SUCCESS=false
        MANUAL_COMMANDS+=("sudo tailscale serve --bg --https=32400 http://localhost:32400")
    fi
else
    echo "  ⚠️  Plex not available yet, skipping HTTPS setup"
    MANUAL_COMMANDS+=("sudo tailscale serve --bg --https=32400 http://localhost:32400")
fi

# Show current configuration (best effort)
echo ""
if sudo tailscale serve status >/dev/null 2>&1; then
    echo "📊 Current Tailscale serve configuration:"
    sudo tailscale serve status 2>/dev/null || echo "  Status unavailable"
else
    echo "📊 Tailscale serve status unavailable (permission denied)"
fi

echo ""
if $TAILSCALE_SUCCESS; then
    echo "🎉 Landing page setup complete!"
    echo ""
    echo "🌐 ACCESSIBLE URLS:"
    echo "   📍 Landing Page: https://$TAILSCALE_HOSTNAME"
    echo "   📸 Immich (Photos): https://$TAILSCALE_HOSTNAME:2283"
    echo "   🎬 Plex (Media): https://$TAILSCALE_HOSTNAME:32400"
    echo ""
    echo "💡 The landing page provides buttons to access each service directly."
else
    echo "⚠️  Landing page HTTP server running, but HTTPS setup needs manual intervention"
    echo ""
    echo "🌐 CURRENTLY ACCESSIBLE:"
    echo "   📍 Landing Page: http://localhost:8080 (local only)"
    echo ""
    echo "🔧 MANUAL SETUP NEEDED FOR HTTPS ACCESS:"
    echo "   Run these commands to enable Tailscale HTTPS:"
    for cmd in "${MANUAL_COMMANDS[@]}"; do
        echo "   $cmd"
    done
    echo ""
    echo "   After running those commands, you'll have:"
    echo "   📍 Landing Page: https://$TAILSCALE_HOSTNAME"
    echo "   📸 Immich (Photos): https://$TAILSCALE_HOSTNAME:2283"
    echo "   🎬 Plex (Media): https://$TAILSCALE_HOSTNAME:32400"
    echo ""
    echo "🚀 QUICK RECOVERY:"
    printf "   "
    printf "%s && " "${MANUAL_COMMANDS[@]}"
    echo "echo '🎉 HTTPS setup complete!'"
fi
echo ""
echo "💡 The landing page provides buttons to access each service directly."
echo "   No complex reverse proxy - just simple, reliable access!"
