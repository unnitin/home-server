#!/usr/bin/env bash
set -euo pipefail
MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/Media}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/Photos}"

ok=0
for d in "$MEDIA_MOUNT" "$PHOTOS_MOUNT" ; do
  if [[ -d "$d" ]]; then
    echo "OK: $d exists"
  else
    echo "MISSING: $d"
    ok=1
  fi
done
exit $ok
