#!/usr/bin/env bash
set -euo pipefail
M1="${MEDIA_MOUNT:-/Volumes/Media}"
M2="${PHOTOS_MOUNT:-/Volumes/Photos}"
M3="${ARCHIVE_MOUNT:-/Volumes/Archive}"
for d in "$M1" "$M2" "$M3"; do
  echo "== $d =="
  if df -h "$d" 2>/dev/null; then
    echo "- OK"
  else
    echo "- Not mounted"
  fi
done
