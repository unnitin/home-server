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

# Every folder to create, as absolute paths, parents before children: each is
# created without -p, so every mode is chosen here. The media layout, the photo
# library and the log root come from the manifest; Immich's and Plex's own
# folders are theirs.
WANT=()
have() {
    local x
    for x in ${WANT[@]+"${WANT[@]}"}; do [[ "$x" == "$1" ]] && return 0; done
    return 1
}
is_tier_root() {
    local t
    for t in $HOMELAB_TIERS; do [[ "$1" == "$(tier_path "$t")" ]] && return 0; done
    return 1
}
want() {  # want PATH: adds PATH, after any parent below its tier's mount point
    local parent
    parent="$(dirname "$1")"
    if [[ "$parent" != / ]] && ! is_tier_root "$parent"; then want "$parent"; fi
    have "$1" || WANT+=("$1")
}
upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

for d in library upload thumbs encoded-video database; do
    want "$HOMELAB_PHOTOS_LIBRARY/$d"
done
for d in metadata transcoding processing logs; do
    want "$HOMELAB_SVC_PLEX_DATA_DIR/$d"   # Plex's own folders, where the manifest keeps its data
done
for lib in $HOMELAB_MEDIA_LIBRARIES; do
    dir_var="HOMELAB_MEDIA_$(upper "$lib")_DIR"
    want "${!dir_var}"
done
for lib in $HOMELAB_MEDIA_LIBRARIES; do
    staging_var="HOMELAB_MEDIA_$(upper "$lib")_STAGING"
    want "${!staging_var}"
done
want "$HOMELAB_MEDIA_FAILED"
want "$HOMELAB_MEDIA_ROOT/music"      # optional Plex/Jellyfin library
for module in media-watcher takeout; do
    want "$HOMELAB_LOG_ROOT/$module"
done

failures=0
created=0

# ensure_layout TIER: create the wanted folders that live on that tier
ensure_layout() {
    local tier="$1" base path mode
    base="$(tier_path "$tier")"
    if ! is_mount_point "$base"; then
        log_warn "$tier is not mounted at $base; skipping it (nothing created)"
        return 0
    fi
    for path in "${WANT[@]}"; do
        [[ "$path" == "$base"/* && ! -e "$path" ]] || continue
        mode=755
        [[ "$path" == "$HOMELAB_PHOTOS_LIBRARY/database" ]] && mode=700
        if ((DRY_RUN)); then
            log_info "Would create $path (mode $mode)"
            continue
        fi
        if mkdir -m "$mode" "$path"; then
            if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
                chown "$SUDO_USER" "$path"
            fi
            log_info "Created $path (mode $mode)"
            created=$((created + 1))
        else
            log_error "Could not create $path"
            failures=$((failures + 1))
        fi
    done
}

for tier in $HOMELAB_TIERS; do
    ensure_layout "$tier"
done

if ((DRY_RUN)); then
    log_info "Dry run: nothing was changed"
elif ((failures)); then
    log_error "$failures folder(s) could not be created"
    exit 1
else
    log_info "Storage layout complete ($created folder(s) created)"
fi
