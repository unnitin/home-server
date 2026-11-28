#!/usr/bin/env bash
# Mount checks shared by the storage scripts. Source it; don't run it.
#
#   source "$SCRIPT_DIR/lib/mount_common.sh"
#   is_mount_point "$(tier_path faststore)" && echo mounted
#
# A folder under /Volumes is not proof that a volume is mounted: macOS leaves
# empty mount-point folders behind (warmstore's was root-owned and empty while
# the RAID was offline), and anything written there lands on the internal disk.
# Only diskutil knows whether a volume is mounted at a path (D22).
#
# Tier mount points come from the manifest (config/homelab.yaml) through
# environment.sh. Tests point a tier elsewhere with HOMELAB_TIER_<TIER>_MOUNT.

set -euo pipefail

# shellcheck source=../../core/environment.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../core/environment.sh"

# True when a volume is mounted exactly at PATH.
is_mount_point() {
    [[ -d "${1:-}" ]] && homelab_is_mounted "$1"
}

# The mount path of a storage tier, from the manifest; fails for an unknown tier.
tier_path() {
    homelab_tier_mount "${1:-}" 2>/dev/null
}
