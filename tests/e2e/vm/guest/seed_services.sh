#!/usr/bin/env bash
# Restore copies of the real Plex and Jellyfin backups into the VM's services.
# Runs INSIDE the VM, before Plex or Jellyfin has started. This proves the
# backups can seed a service, and gives the rehearsal realistic libraries.
#
#   seed_services.sh SEED_DIR
#
# SEED_DIR (pushed from the host, copies only) holds:
#   plex/com.plexapp.plugins.library.db        a dated Plex automatic backup
#   plex/com.plexapp.plugins.library.blobs.db  the matching blobs backup
#   jellyfin-config/                           Jellyfin config, cache/log excluded
#
# Only the Plex library database is restored. The VM's Plex creates its own
# identity on first start and is never signed in, so it can't be mistaken for
# the real server.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh"

SEED="${1:?usage: seed_services.sh SEED_DIR}"
FS=/Volumes/faststore
log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

for app in "Plex Media Server" "Jellyfin"; do
    if pgrep -f "/Applications/$app.app" >/dev/null 2>&1; then
        log_error "$app is running; seed before it starts"
        exit 1
    fi
done

if [[ -f "$SEED/plex/com.plexapp.plugins.library.db" ]]; then
    db="$FS/plex/metadata/Plug-in Support/Databases"
    mkdir -p "$db"
    cp "$SEED/plex/com.plexapp.plugins.library.db" "$db/"
    if [[ -f "$SEED/plex/com.plexapp.plugins.library.blobs.db" ]]; then
        cp "$SEED/plex/com.plexapp.plugins.library.blobs.db" "$db/"
    fi
    log_info "Plex: library database restored to $db"
fi

if [[ -d "$SEED/jellyfin-config" ]]; then
    rsync -a "$SEED/jellyfin-config/" "$FS/jellyfin/config/"
    log_info "Jellyfin: config restored to $FS/jellyfin/config"
fi
