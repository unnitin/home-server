#!/usr/bin/env bash
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"
require_guard
parse_disks COLD_DISKS
COLD_RAID_NAME="${COLD_RAID_NAME:-coldstore}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-/Volumes/Archive}"

delete_raid_by_name "$COLD_RAID_NAME"

case "${#DISKS[@]}" in
  2)
    dev=$(create_mirror "${COLD_RAID_NAME}_mirror" "${DISKS[0]}" "${DISKS[1]}")
    ;;
  4)
    m1=$(create_mirror "${COLD_RAID_NAME}_m1" "${DISKS[0]}" "${DISKS[1]}")
    m2=$(create_mirror "${COLD_RAID_NAME}_m2" "${DISKS[2]}" "${DISKS[3]}")
    dev=$(create_stripe_of_mirrors "$COLD_RAID_NAME" "$m1" "$m2")
    ;;
  *)
    echo "Provide 2 or 4 disks in COLD_DISKS"; exit 1;;
esac

format_and_mount "$dev" "$COLD_RAID_NAME" "$ARCHIVE_MOUNT"
echo "✅ HDD array '$COLD_RAID_NAME' ready at $ARCHIVE_MOUNT"
