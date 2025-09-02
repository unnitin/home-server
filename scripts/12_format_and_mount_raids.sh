#!/usr/bin/env bash
set -euo pipefail
SSD_RAID_NAME="${SSD_RAID_NAME:-warmstore}"
NVME_RAID_NAME="${NVME_RAID_NAME:-faststore}"
MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/Media}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/Photos}"

echo "Ensuring APFS volumes are mounted..."
diskutil mount "$SSD_RAID_NAME" || true
diskutil mount "$NVME_RAID_NAME" || true

sudo mkdir -p "$MEDIA_MOUNT"/{Movies,TV,Music,Other}
sudo mkdir -p "$PHOTOS_MOUNT"/{originals,library,backup}

echo "Created directory structure under $MEDIA_MOUNT and $PHOTOS_MOUNT."
