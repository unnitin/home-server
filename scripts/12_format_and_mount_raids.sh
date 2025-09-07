#!/usr/bin/env bash
set -euo pipefail
sudo mkdir -p "${MEDIA_MOUNT:-/Volumes/Media}" "${PHOTOS_MOUNT:-/Volumes/Photos}" "${ARCHIVE_MOUNT:-/Volumes/Archive}"
echo "Ensured mount points exist."
