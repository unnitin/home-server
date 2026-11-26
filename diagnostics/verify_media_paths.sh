#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

# Get mount points from environment or use defaults
MEDIA_MOUNT="${MEDIA_MOUNT:-$(diag_tier_mount warmstore /Volumes/warmstore)}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-$(diag_tier_mount faststore /Volumes/faststore)}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-$(diag_tier_mount coldstore /Volumes/coldstore)}"

section "Storage Mount Points"

# check_mount_point MOUNT PURPOSE TIER [optional]
#   Thresholds are the tier's own (manifest: warn_pct, crit_pct). An optional
#   tier that isn't there is a warning, not a failure (coldstore: no service needs it).
check_mount_point() {
    local mount_point="$1"
    local purpose="$2"
    local tier="${3:-}" optional="${4:-}"
    local upper warn_var crit_var warn_pct crit_pct
    upper=$(printf '%s' "$tier" | tr '[:lower:]' '[:upper:]')
    warn_var="HOMELAB_TIER_${upper}_WARN_PCT"; crit_var="HOMELAB_TIER_${upper}_CRIT_PCT"
    warn_pct="${!warn_var:-80}"; crit_pct="${!crit_var:-95}"

    echo -e "\n${YELLOW}Checking $mount_point ($purpose)${NC}"

    if [[ -d "$mount_point" ]]; then
        ok "Directory exists: $mount_point"

        # Actually mounted, by diskutil's account: df on an empty mount-point
        # folder reports the internal disk (D22)
        if diag_is_mounted "$mount_point"; then
            # Get mount info
            mount_info=$(df -h "$mount_point" | tail -1)
            device=$(echo "$mount_info" | awk '{print $1}')
            size=$(echo "$mount_info" | awk '{print $2}')
            used=$(echo "$mount_info" | awk '{print $3}')
            available=$(echo "$mount_info" | awk '{print $4}')
            percent_used=$(echo "$mount_info" | awk '{print $5}')

            ok "Mounted: $device"
            ok "Size: $size, Used: $used ($percent_used), Available: $available"

            # Check usage levels
            usage_num=$(echo "$percent_used" | sed 's/%//')
            if [[ $usage_num -ge $crit_pct ]]; then
                fail "Critical: disk usage at or above ${crit_pct}% ($percent_used)"
            elif [[ $usage_num -ge $warn_pct ]]; then
                warn "High disk usage: at or above ${warn_pct}% ($percent_used)"
            fi

            # Check write permissions
            if [[ -w "$mount_point" ]]; then
                ok "Write permissions: OK"
            else
                warn "No write permissions (may need to fix ownership)"
            fi

            # Check if mount point contains expected content
            # find exits 1 on an unreadable folder (.Spotlight-V100, .Trashes);
            # under pipefail that used to end the script (D24).
            item_count=$( { find "$mount_point" -maxdepth 2 -type f 2>/dev/null || true; } | wc -l | tr -d ' ')
            if [[ $item_count -gt 0 ]]; then
                ok "Content found: $item_count files"
            else
                warn "Mount point appears empty (normal for new setup)"
            fi

        elif [[ "$optional" == optional ]]; then
            warn "Not mounted (an empty mount-point folder): $mount_point"
        else
            fail "Not mounted: the folder is an empty mount point, not the volume"
        fi
    elif [[ "$optional" == optional ]]; then
        warn "Not attached: $mount_point"
    else
        fail "Directory does not exist: $mount_point"
        echo "  💡 This may be normal if storage arrays haven't been created yet"
        echo "     See docs/STORAGE.md for setup instructions"
    fi
}

# Check each configured mount point
check_mount_point "$PHOTOS_MOUNT" "Immich Photos - faststore" faststore
check_mount_point "$MEDIA_MOUNT" "Plex Media - warmstore" warmstore
check_mount_point "$ARCHIVE_MOUNT" "Archive Storage - coldstore" coldstore optional

# Summary of storage architecture
echo -e "\n${YELLOW}Storage Architecture Summary${NC}"
echo "faststore (NVMe):  $PHOTOS_MOUNT  → Immich photos (high-speed)"
echo "warmstore (SSD):   $MEDIA_MOUNT   → Plex media (good-speed)"
echo "coldstore (HDD):   $ARCHIVE_MOUNT → Archive storage (capacity)"

# Check for any other mounted volumes that might be relevant
echo -e "\n${YELLOW}Other mounted volumes${NC}"
other_volumes=$(ls /Volumes/ 2>/dev/null | grep -v "^Macintosh HD$" | grep -v "$(basename "$MEDIA_MOUNT")$" | grep -v "$(basename "$PHOTOS_MOUNT")$" | grep -v "$(basename "$ARCHIVE_MOUNT")$" || true)

if [[ -n "$other_volumes" ]]; then
    echo "Additional volumes found:"
    while IFS= read -r volume; do
        if [[ -n "$volume" ]]; then
            echo "  - /Volumes/$volume"
            df -h "/Volumes/$volume" 2>/dev/null | tail -1 | awk '{print "    " $2 " total, " $4 " available (" $5 " used)"}'
        fi
    done <<< "$other_volumes"
else
    echo "No additional volumes found"
fi

print_summary
