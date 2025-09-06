#!/usr/bin/env bash
set -euo pipefail
for d in "${MEDIA_MOUNT:-/Volumes/Media}" "${PHOTOS_MOUNT:-/Volumes/Photos}" "${ARCHIVE_MOUNT:-/Volumes/Archive}"; do
  echo "== $d =="
  df -h "$d" 2>&1 || echo "not mounted"
done
