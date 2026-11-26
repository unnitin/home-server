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
# --foreground: stay running for as long as the landing server does. The LaunchD
#   job uses it: the job has KeepAlive, so a script that returns after starting
#   the server in the background is relaunched, and restarts the server, every
#   cycle (D28).
WAIT=90
FOREGROUND=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --setup-mode) WAIT=0 ;;
        --foreground) FOREGROUND=true ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

banner "Landing page and tailnet HTTPS"

TAILSCALE_HOSTNAME=$(ts_hostname)
TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-your-device.your-tailnet.ts.net}"
echo "Tailscale hostname: $TAILSCALE_HOSTNAME"

echo "Restarting landing page server on 127.0.0.1:8080..."
# Stop the landing server already listening on :8080, whatever its interpreter is
# called (a server started by hand may show as ".../Python -m http.server 8080").
# Only the listener is considered: a pattern match on command lines would also
# kill any shell or editor that merely mentions it (D28).
for pid in $(lsof -nP -tiTCP:8080 -sTCP:LISTEN 2>/dev/null || true); do
    if ps -o command= -p "$pid" 2>/dev/null | grep -q -- "-m http[.]server 8080"; then
        echo "Stopping the previous landing server (PID $pid)"
        kill "$pid" 2>/dev/null || true
        sleep 1
    fi
done
cd "$REPO_ROOT/web"
nohup python3 -m http.server 8080 --bind 127.0.0.1 > /dev/null 2>&1 &
SERVER_PID=$!
echo "✅ Started landing page server (PID: $SERVER_PID)"
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

if $FOREGROUND; then
    echo ""
    echo "Serving in the foreground until the landing server exits (PID $SERVER_PID)"
    rc=0
    wait "$SERVER_PID" || rc=$?
    echo "$(date): landing page server exited ($rc)"
    exit "$rc"
fi
