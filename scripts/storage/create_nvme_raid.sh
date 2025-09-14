#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib/raid_common.sh"
require_guard
parse_disks NVME_DISKS

for d in "${DISKS[@]}"; do
  [[ "$d" =~ ^disk[0-9]+$ ]] || { echo "Use WHOLE disks like 'disk6', not '$d'"; exit 1; }
done

NVME_RAID_NAME="${NVME_RAID_NAME:-faststore}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/Photos}"

delete_raids_containing_disks "${DISKS[@]}"
delete_raid_by_name "$NVME_RAID_NAME"

case "${#DISKS[@]}" in
  2)
    dev=$(create_mirror "$NVME_RAID_NAME" "${DISKS[0]}" "${DISKS[1]}")
    ;;
  4)
    m1=$(create_mirror "${NVME_RAID_NAME}_m1" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "${NVME_RAID_NAME}_m2" "${DISKS[2]}" "${DISKS[3]}")
    dev=$(create_stripe_of_mirrors "$NVME_RAID_NAME" "$m1" "$m2")
    ;;
  *)
    echo "Provide 2 or 4 disks in NVME_DISKS"; exit 1;;
esac

format_and_mount "$dev" "$NVME_RAID_NAME" "$PHOTOS_MOUNT"
echo "✅ NVMe array '$NVME_RAID_NAME' ready at $PHOTOS_MOUNT"
