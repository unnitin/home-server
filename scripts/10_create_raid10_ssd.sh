#!/usr/bin/env bash
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"
require_guard
parse_disks SSD_DISKS

# Validate whole disks only
for d in "${DISKS[@]}"; do
  [[ "$d" =~ ^disk[0-9]+$ ]] || { echo "Use WHOLE disks like 'disk6', not '$d'"; exit 1; }
done

SSD_RAID_NAME="${SSD_RAID_NAME:-warmstore}"
MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/Media}"

delete_raids_containing_disks "${DISKS[@]}"
delete_raid_by_name "$SSD_RAID_NAME"

case "${#DISKS[@]}" in
  2)
    dev=$(create_mirror "$SSD_RAID_NAME" "${DISKS[0]}" "${DISKS[1]}")
    ;;
  4)
    m1=$(create_mirror "${SSD_RAID_NAME}_m1" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "${SSD_RAID_NAME}_m2" "${DISKS[2]}" "${DISKS[3]}")
    dev=$(create_stripe_of_mirrors "$SSD_RAID_NAME" "$m1" "$m2")
    ;;
  *)
    echo "Provide 2 or 4 disks in SSD_DISKS"; exit 1;;
esac

format_and_mount "$dev" "$SSD_RAID_NAME" "$MEDIA_MOUNT"
echo "✅ SSD array '$SSD_RAID_NAME' ready at $MEDIA_MOUNT"
