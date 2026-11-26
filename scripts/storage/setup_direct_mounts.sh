#!/usr/bin/env bash
# Create the expected folder layout on each storage tier, without symlinks.
# Run at login by LaunchD (io.homelab.storage) and by setup_full.sh.
#
#   setup_direct_mounts.sh [--dry-run]
#
# Safe to run any time (D22):
# - Works only on a volume that is actually mounted (diskutil). An empty
#   mount-point folder is skipped, so nothing lands on the internal disk and
#   Plex and Jellyfin never see an empty library in place of a missing one.
# - Creates missing folders only. It never deletes anything and never changes
#   the owner or mode of anything that already exists. A new Immich database
#   folder is created 0700, which Postgres requires.
# - Needs no sudo. Run as root (setup_full.sh uses sudo), it hands only the
#   folders it created to the invoking user.
#
# Exits 0 when every mounted tier has its layout (a tier that isn't mounted is
# reported and skipped), 1 when a folder could not be created on a mounted one.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mount_common.sh
source "$SCRIPT_DIR/lib/mount_common.sh"

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

DRY_RUN=0
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
        sed -n '2,19p' "$0"
        exit 0
        ;;
    *)
        log_error "Unknown option: $1 (try --help)"
        exit 2
        ;;
esac

# Parents before children: each folder is created without -p.
FASTSTORE_DIRS=(
    immich
    immich/library
    immich/upload
    immich/thumbs
    immich/encoded-video
    immich/database
    immich/logs
    plex
    plex/metadata
    plex/transcoding
    plex/processing
    plex/logs
)
WARMSTORE_DIRS=(
    movies
    tv-shows
    music
    collections
    staging
    staging/movies
    staging/tv-shows
    staging/collections
    logs
    logs/system
    logs/media-processing
    logs/web
)

failures=0
created=0

# ensure_layout TIER DIR...
ensure_layout() {
    local tier="$1" base dir mode
    shift
    base="$(tier_path "$tier")"
    if ! is_mount_point "$base"; then
        log_warn "$tier is not mounted at $base; skipping it (nothing created)"
        return 0
    fi
    for dir in "$@"; do
        [[ -e "$base/$dir" ]] && continue
        mode=755
        [[ "$dir" == immich/database ]] && mode=700
        if ((DRY_RUN)); then
            log_info "Would create $base/$dir (mode $mode)"
            continue
        fi
        if mkdir -m "$mode" "$base/$dir"; then
            if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
                chown "$SUDO_USER" "$base/$dir"
            fi
            log_info "Created $base/$dir (mode $mode)"
            created=$((created + 1))
        else
            log_error "Could not create $base/$dir"
            failures=$((failures + 1))
        fi
    done
}

ensure_layout faststore "${FASTSTORE_DIRS[@]}"
ensure_layout warmstore "${WARMSTORE_DIRS[@]}"

if ((DRY_RUN)); then
    log_info "Dry run: nothing was changed"
elif ((failures)); then
    log_error "$failures folder(s) could not be created"
    exit 1
else
    log_info "Storage layout complete ($created folder(s) created)"
fi
