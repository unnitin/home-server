#!/usr/bin/env bash
# Start the landing page and publish services to the tailnet.
#
# The landing page is served on 127.0.0.1:8080. Tailnet HTTPS for it and every
# other service comes from scripts/infrastructure/apply_tailscale_serve.sh, which
# applies config/tailscale_serve.txt. This script used to run `tailscale serve reset`,
# which wiped every other mapping (Jellyfin's, and any MCP mapping) at each boot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../infrastructure/lib/tailscale.sh
source "$REPO_ROOT/scripts/infrastructure/lib/tailscale.sh"

banner() { echo; echo "=== $* ==="; }

# --setup-mode: don't wait for services that aren't up yet (setup runs before they start)
WAIT=90
if [[ "${1:-}" == "--setup-mode" ]]; then
    WAIT=0
    shift
fi

banner "Landing page and tailnet HTTPS"

TAILSCALE_HOSTNAME=$(ts_hostname)
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-your-device.your-tailnet.ts.net}"
echo "Tailscale hostname: $TAILSCALE_HOSTNAME"

echo "Restarting landing page server on 127.0.0.1:8080..."
pkill -f "python3 -m http.server 8080" 2>/dev/null || true
cd "$REPO_ROOT/web"
nohup python3 -m http.server 8080 --bind 127.0.0.1 > /dev/null 2>&1 &
echo "✅ Started landing page server (PID: $!)"
sleep 2

echo ""
echo "🔧 Applying tailnet HTTPS mappings from config/tailscale_serve.txt..."
if "$REPO_ROOT/scripts/infrastructure/apply_tailscale_serve.sh" --wait "$WAIT"; then
    echo "🎉 Landing page setup complete"
else
    echo "⚠️  Some mappings could not be applied. Re-run: scripts/infrastructure/apply_tailscale_serve.sh"
fi

echo ""
echo "🌐 Tailnet URLs:"
echo "   📍 Landing page: https://$TAILSCALE_HOSTNAME"
echo "   📸 Immich:       https://$TAILSCALE_HOSTNAME:2283"
echo "   🎬 Plex:         https://$TAILSCALE_HOSTNAME:32400"
echo "   🎞️  Jellyfin:     https://$TAILSCALE_HOSTNAME:8096"
