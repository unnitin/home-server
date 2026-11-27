#!/usr/bin/env bash
# Restart a native app from the manifest (Plex, Jellyfin): quit it, then start it
# the way its LaunchD job does, waiting for its health URL.
#
#   restart_native_app.sh plex
#
# Run by the MCP service_restart tool as a job. Refuses if the app's data tier
# isn't mounted, before quitting anything. The LaunchD job's watcher (D32)
# tolerates the short gap: it acts only after three failed checks in a row.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/native_app.sh
source "$SCRIPT_DIR/lib/native_app.sh"

svc="${1:?usage: restart_native_app.sh SERVICE}"
tier=$(_svc "$svc" DATA_TIER)
if [[ -n "$tier" ]] && ! homelab_is_mounted "$(homelab_tier_mount "$tier")"; then
    echo "❌ $tier is not mounted: $svc's data lives there. Not restarting it." >&2
    exit 1
fi
echo "::stage quitting"
quit_native_app "$svc"
echo "::progress 40"
echo "::stage starting"
start_native_app "$svc"
echo "::progress 100"
