#!/usr/bin/env bash
# Rebuild one or more storage arrays in a re-runnable way.
# Stops services, deletes existing AppleRAID sets (by name), recreates based on disk lists, remounts, restarts services.
#
# Usage examples:
#   RAID_I_UNDERSTAND_DATA_LOSS=1 ./scripts/09_rebuild_storage.sh warmstore
#   RAID_I_UNDERSTAND_DATA_LOSS=1 ./scripts/09_rebuild_storage.sh faststore warmstore
#
set -euo pipefail
source "$(pwd)/scripts/_raid_common.sh"

if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
  echo "This will delete and recreate RAID sets. Set RAID_I_UNDERSTAND_DATA_LOSS=1 to proceed."
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "Specify which arrays to rebuild: faststore | warmstore | coldstore"
  exit 1
fi

stop_services() {
  echo "Stopping Immich (docker compose)..."
  ( cd services/immich && docker compose down ) || true
  echo "Attempting to stop Plex (native) ..."
  pkill -f "Plex Media Server" || true
}

start_services() {
  echo "Starting Immich ..."
  ( cd services/immich && docker compose up -d ) || true
  echo "Starting Plex (if installed) ..."
  open -ga "Plex Media Server" || true
}

stop_services

for target in "$@"; do
  case "$target" in
    warmstore)
      echo "Rebuilding warmstore (SSD)..."
      ./scripts/10_create_raid10_ssd.sh
      ;;
    faststore)
      echo "Rebuilding faststore (NVMe)..."
      ./scripts/11_create_raid10_nvme.sh
      ;;
    coldstore)
      echo "Rebuilding coldstore (HDD/archive)..."
      ./scripts/13_create_raid_coldstore.sh
      ;;
    *)
      echo "Unknown target: $target"; exit 1;;
  esac
done

./scripts/12_format_and_mount_raids.sh || true

start_services

echo "Rebuild complete."
