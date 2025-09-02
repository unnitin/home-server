#!/usr/bin/env bash
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"

require_confirm
parse_disks COLD_DISKS

COLD_RAID_NAME="${COLD_RAID_NAME:-coldstore}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-/Volumes/Archive}"

# Delete existing set with same name (re-runnable behavior)
delete_raid_by_name "$COLD_RAID_NAME" || true

case "${#DISKS[@]}" in
  2)
    echo "Creating RAID1 mirror '$COLD_RAID_NAME' (2 disks)..."
    sudo diskutil appleRAID create mirror "$COLD_RAID_NAME" APFS "${DISKS[0]}" "${DISKS[1]}"
    ;;
  4)
    echo "Creating RAID10 '$COLD_RAID_NAME' (two mirrors striped, 4 disks)..."
    m1=$(create_mirror "coldstore_mirror_a" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "coldstore_mirror_b" "${DISKS[2]}" "${DISKS[3]}")
    create_stripe_from_mirrors "$COLD_RAID_NAME" "$m1" "$m2"
    ;;
  *)
    echo "ERROR: Provide 2 or 4 disks for COLD_DISKS. Got: ${#DISKS[@]}"; exit 1
    ;;
esac

post_create_mount_and_prepare "$COLD_RAID_NAME" "$ARCHIVE_MOUNT"
echo "Coldstore created: $COLD_RAID_NAME mounted at $ARCHIVE_MOUNT"
