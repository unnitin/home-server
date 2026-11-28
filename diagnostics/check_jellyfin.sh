#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

JELLYFIN_URL="${JELLYFIN_URL:-http://localhost:${HOMELAB_SVC_JELLYFIN_PORTS:-8096}}"

section "Jellyfin"

check_process "Jellyfin.app/Contents/MacOS/" "Jellyfin" || true
tcp_open localhost 8096 || true

if curl -fsS -m 4 "$JELLYFIN_URL/health" 2>/dev/null | grep -q "Healthy"; then
    ok "Health endpoint reports Healthy: $JELLYFIN_URL/health"
else
    fail "Health endpoint not healthy: $JELLYFIN_URL/health"
fi

version=$(curl -fsS -m 4 "$JELLYFIN_URL/System/Info/Public" 2>/dev/null \
    | sed -n 's/.*"Version":"\([^"]*\)".*/\1/p' || true)
if [[ -n "$version" ]]; then
    info "Version: $version"
fi

check_launchd_service "io.homelab.jellyfin" "Jellyfin" || true

print_summary
