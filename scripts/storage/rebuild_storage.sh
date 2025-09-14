#!/usr/bin/env bash
set -euo pipefail
if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
  echo "Set RAID_I_UNDERSTAND_DATA_LOSS=1"; exit 2
fi
[[ $# -gt 0 ]] || { echo "Usage: $0 faststore|warmstore|coldstore [...]"; exit 1; }

echo "Stopping Immich and Plex..."
( cd services/immich && scripts/infrastructure/compose_wrapper.sh services/immich down ) || true
pkill -f "Plex Media Server" || true

for t in "$@"; do
  case "$t" in
    warmstore)  ./scripts/storage/create_ssd_raid.sh ;;
    faststore)  ./scripts/storage/create_nvme_raid.sh ;;
    coldstore)  ./scripts/storage/create_hdd_raid.sh ;;
    *) echo "Unknown target: $t"; exit 1;;
  esac
done

./scripts/storage/format_and_mount.sh || true

echo "Restarting services..."
( cd services/immich && scripts/infrastructure/compose_wrapper.sh services/immich up -d ) || true
open -ga "Plex Media Server" || true
echo "Rebuild complete."
