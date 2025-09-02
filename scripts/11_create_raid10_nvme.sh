#!/usr/bin/env bash
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"

require_confirm
parse_disks NVME_DISKS

NVME_RAID_NAME="${NVME_RAID_NAME:-faststore}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/Photos}"

# If an existing set with this name exists, delete it (re-runnable behavior)
delete_raid_by_name "$NVME_RAID_NAME" || true

case "${#DISKS[@]}" in
  2)
    echo "Creating RAID1 mirror '$NVME_RAID_NAME' on ${DISKS[*]} (2-disk mirror)..."
    sudo diskutil appleRAID create mirror "$NVME_RAID_NAME" APFS "${DISKS[0]}" "${DISKS[1]}"
    ;;
  4)
    echo "Creating RAID10 '$NVME_RAID_NAME' (two mirrors striped)..."
    m1=$(create_mirror "faststore_mirror_a" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "faststore_mirror_b" "${DISKS[2]}" "${DISKS[3]}")
    create_stripe_from_mirrors "$NVME_RAID_NAME" "$m1" "$m2"
    ;;
  *)
    echo "ERROR: Provide exactly 2 or 4 disks for NVME_RAID_NAME ($NVME_RAID_NAME). Got: ${#DISKS[@]}"; exit 1
    ;;
esac

post_create_mount_and_prepare "$NVME_RAID_NAME" "$PHOTOS_MOUNT"
echo "NVMe array created: $NVME_RAID_NAME mounted at $PHOTOS_MOUNT"
