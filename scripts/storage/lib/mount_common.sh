#!/usr/bin/env bash
# Mount checks shared by the storage scripts. Source it; don't run it.
#
#   source "$SCRIPT_DIR/lib/mount_common.sh"
#   is_mount_point /Volumes/faststore && echo mounted
#
# A folder under /Volumes is not proof that a volume is mounted: macOS leaves
# empty mount-point folders behind (warmstore's was root-owned and empty while
# the RAID was offline), and anything written there lands on the internal disk.
# Only diskutil knows whether a volume is mounted at a path (D22).

set -euo pipefail

# Where the storage tiers mount. Tests point this at a temporary folder.
HOMELAB_VOLUMES_ROOT="${HOMELAB_VOLUMES_ROOT:-/Volumes}"

# True when a volume is mounted exactly at PATH.
is_mount_point() {
    local path="$1" mount_point
    [[ -d "$path" ]] || return 1
    mount_point=$(diskutil info -plist "$path" 2>/dev/null |
        plutil -extract MountPoint raw -o - - 2>/dev/null) || return 1
    [[ "$mount_point" == "$path" ]]
}

# The mount path of a storage tier: faststore, warmstore or coldstore.
tier_path() {
    case "$1" in
        faststore | warmstore) echo "$HOMELAB_VOLUMES_ROOT/$1" ;;
        coldstore) echo "$HOMELAB_VOLUMES_ROOT/Archive" ;; # volume label is Archive
        *) return 1 ;;
    esac
}
