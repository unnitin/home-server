#!/usr/bin/env bash
# Wait until the storage a service needs is mounted, then exit 0.
# Used by LaunchD jobs before they start a service.
#
#   wait_for_storage.sh [TIER...]     TIER: a tier in the manifest (default: faststore warmstore)
#
# A tier counts as ready only when diskutil reports a volume mounted at it; an
# empty mount-point folder is not enough (D22). The photos tier also needs its
# photo library folder. Waits up to WAIT_TIMEOUT seconds (default 300), then exits 1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mount_common.sh
source "$SCRIPT_DIR/lib/mount_common.sh"

TIMEOUT="${WAIT_TIMEOUT:-300}"
INTERVAL="${WAIT_INTERVAL:-2}"
tiers=("$@")
((${#tiers[@]})) || tiers=(faststore warmstore)

ready() {
    local tier="$1" path
    path="$(tier_path "$tier")" || return 2
    is_mount_point "$path" || return 1
    [[ "$HOMELAB_PHOTOS_LIBRARY" != "$path"/* || -d "$HOMELAB_PHOTOS_LIBRARY" ]]
}

echo "$(date): Waiting for storage: ${tiers[*]}"
for tier in "${tiers[@]}"; do
    if ! tier_path "$tier" >/dev/null; then
        echo "ERROR: unknown storage tier '$tier' (known: $HOMELAB_TIERS)" >&2
        exit 2
    fi
    waited=0
    until ready "$tier"; do
        if ((waited >= TIMEOUT)); then
            echo "ERROR: $tier not mounted at $(tier_path "$tier") after ${TIMEOUT}s" >&2
            exit 1
        fi
        echo "Waiting for $tier... (${waited}/${TIMEOUT}s)"
        sleep "$INTERVAL"
        waited=$((waited + INTERVAL))
    done
    echo "✅ $tier mounted at $(tier_path "$tier")"
done
echo "✅ Storage ready: ${tiers[*]}"
