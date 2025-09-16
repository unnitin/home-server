#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

# Get mount points from environment or use defaults
MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/warmstore}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/faststore}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-/Volumes/Archive}"

section "Storage Mount Points"

check_mount_point() {
    local mount_point="$1"
    local purpose="$2"
    
    echo -e "\n${YELLOW}Checking $mount_point ($purpose)${NC}"
    
    if [[ -d "$mount_point" ]]; then
        ok "Directory exists: $mount_point"
        
        # Check if it's actually mounted (not just an empty directory)
        if df "$mount_point" >/dev/null 2>&1; then
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
            if [[ $usage_num -gt 95 ]]; then
                fail "Critical: Disk usage >95% ($percent_used)"
            elif [[ $usage_num -gt 90 ]]; then
                warn "High disk usage >90% ($percent_used)"
            elif [[ $usage_num -gt 80 ]]; then
                warn "Moderate disk usage >80% ($percent_used)"
            fi
            
            # Check write permissions
            if [[ -w "$mount_point" ]]; then
                ok "Write permissions: OK"
            else
                warn "No write permissions (may need to fix ownership)"
            fi
            
            # Check if mount point contains expected content
            item_count=$(find "$mount_point" -maxdepth 2 -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ $item_count -gt 0 ]]; then
                ok "Content found: $item_count files"
            else
                warn "Mount point appears empty (normal for new setup)"
            fi
            
        else
            fail "Directory exists but not properly mounted"
        fi
    else
        fail "Directory does not exist: $mount_point"
        echo "  💡 This may be normal if storage arrays haven't been created yet"
        echo "     See docs/STORAGE.md for setup instructions"
    fi
}

# Check each configured mount point
check_mount_point "$PHOTOS_MOUNT" "Immich Photos - faststore"
check_mount_point "$MEDIA_MOUNT" "Plex Media - warmstore"  
check_mount_point "$ARCHIVE_MOUNT" "Archive Storage - coldstore"

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