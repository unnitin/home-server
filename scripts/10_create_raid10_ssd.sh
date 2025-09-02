#!/usr/bin/env bash
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"

require_confirm
parse_disks SSD_DISKS

SSD_RAID_NAME="${SSD_RAID_NAME:-warmstore}"
MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/Media}"

# If an existing set with this name exists, delete it (re-runnable behavior)
delete_raid_by_name "$SSD_RAID_NAME" || true

case "${#DISKS[@]}" in
  2)
    echo "Creating RAID1 mirror '$SSD_RAID_NAME' on ${DISKS[*]} (2-disk mirror)..."
    sudo diskutil appleRAID create mirror "$SSD_RAID_NAME" APFS "${DISKS[0]}" "${DISKS[1]}"
    ;;
  4)
    echo "Creating RAID10 '$SSD_RAID_NAME' (two mirrors striped)..."
    m1=$(create_mirror "warmstore_mirror_a" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "warmstore_mirror_b" "${DISKS[2]}" "${DISKS[3]}")
    create_stripe_from_mirrors "$SSD_RAID_NAME" "$m1" "$m2"
    ;;
  *)
    echo "ERROR: Provide exactly 2 or 4 disks for SSD_RAID_NAME ($SSD_RAID_NAME). Got: ${#DISKS[@]}"; exit 1
    ;;
esac

post_create_mount_and_prepare "$SSD_RAID_NAME" "$MEDIA_MOUNT"
echo "SSD array created: $SSD_RAID_NAME mounted at $MEDIA_MOUNT"
