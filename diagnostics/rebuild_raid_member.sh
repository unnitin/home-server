#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <RAID-SET-UUID> <new-diskX>"
  exit 1
fi
uuid="$1"
disk="$2"
echo "Attempting to add $disk back to RAID set $uuid ..."
sudo diskutil appleRAID add member "$uuid" "$disk"
echo "Done. Monitor rebuild with 'diskutil appleRAID list'."
