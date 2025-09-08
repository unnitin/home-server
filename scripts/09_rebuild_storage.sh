#!/usr/bin/env bash
set -euo pipefail
if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
  echo "Set RAID_I_UNDERSTAND_DATA_LOSS=1"; exit 2
fi
[[ $# -gt 0 ]] || { echo "Usage: $0 faststore|warmstore|coldstore [...]"; exit 1; }

echo "Stopping Immich and Plex..."
( cd services/immich && scripts/compose_helper.sh services/immich down ) || true
pkill -f "Plex Media Server" || true

for t in "$@"; do
  case "$t" in
    warmstore)  ./scripts/10_create_raid10_ssd.sh ;;
    faststore)  ./scripts/11_create_raid10_nvme.sh ;;
    coldstore)  ./scripts/13_create_raid_coldstore.sh ;;
    *) echo "Unknown target: $t"; exit 1;;
  esac
done

./scripts/12_format_and_mount_raids.sh || true

echo "Restarting services..."
( cd services/immich && scripts/compose_helper.sh services/immich up -d ) || true
open -ga "Plex Media Server" || true
echo "Rebuild complete."
