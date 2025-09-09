#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "RAID Array Status"

# Check if diskutil is available (macOS only)
if ! command -v diskutil >/dev/null 2>&1; then
    fail "diskutil not available (this check is macOS-only)"
    print_summary
    exit 1
fi

ok "diskutil available"

# Check for AppleRAID sets
echo -e "\n${YELLOW}Checking AppleRAID sets...${NC}"
if raid_output=$(diskutil appleRAID list 2>/dev/null); then
    if echo "$raid_output" | grep -q "No AppleRAID sets found"; then
        warn "No AppleRAID sets found"
        echo "  → This is normal if using single disks or external storage"
    else
        ok "AppleRAID sets found"
        echo "$raid_output"
        
        # Parse and check each RAID set status
        while IFS= read -r line; do
            if [[ $line =~ Name:[[:space:]]+(.+) ]]; then
                raid_name="${BASH_REMATCH[1]}"
                echo -e "\n${YELLOW}Checking RAID set: $raid_name${NC}"
            elif [[ $line =~ Status:[[:space:]]+(.+) ]]; then
                raid_status="${BASH_REMATCH[1]}"
                case "$raid_status" in
                    "Online")
                        ok "RAID $raid_name status: $raid_status"
                        ;;
                    "Degraded")
                        warn "RAID $raid_name status: $raid_status (drive may have failed)"
                        ;;
                    "Failed"|"Offline")
                        fail "RAID $raid_name status: $raid_status"
                        ;;
                    *)
                        warn "RAID $raid_name status: $raid_status (unknown status)"
                        ;;
                esac
            fi
        done <<< "$raid_output"
    fi
else
    warn "Failed to list AppleRAID sets"
fi

# Check individual disk health for known arrays
echo -e "\n${YELLOW}Checking storage mount points...${NC}"
for mount_point in "/Volumes/Media" "/Volumes/Photos" "/Volumes/Archive"; do
    if [[ -d "$mount_point" ]]; then
        ok "Mount point exists: $mount_point"
        
        # Get disk info for this mount
        if disk_info=$(df "$mount_point" 2>/dev/null | tail -1); then
            device=$(echo "$disk_info" | awk '{print $1}')
            usage=$(echo "$disk_info" | awk '{print $5}')
            ok "  Device: $device, Usage: $usage"
            
            # Check if usage is getting high
            usage_num=$(echo "$usage" | sed 's/%//')
            if [[ $usage_num -gt 90 ]]; then
                fail "  High disk usage: $usage (>90%)"
            elif [[ $usage_num -gt 80 ]]; then
                warn "  Moderate disk usage: $usage (>80%)"
            fi
        fi
    else
        warn "Mount point not available: $mount_point"
    fi
done

# Check for any failed disks in system
echo -e "\n${YELLOW}Checking for failed disks...${NC}"
if failed_disks=$(diskutil list | grep -i "fail\|error\|problem" || true); then
    if [[ -n "$failed_disks" ]]; then
        fail "Potential disk issues found:"
        echo "$failed_disks"
    else
        ok "No obvious disk failures detected"
    fi
else
    ok "No disk failures detected"
fi

print_summary