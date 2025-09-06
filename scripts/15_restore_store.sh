#!/usr/bin/env bash
set -euo pipefail
SRC_DIR="${1:-}"; DEST_KEY="${2:-}"
[[ -n "$SRC_DIR" && -n "$DEST_KEY" ]] || { echo "Usage: $0 <source-dir> <warmstore|faststore>"; exit 1; }
case "$DEST_KEY" in
  warmstore) DEST_DIR="${MEDIA_MOUNT:-/Volumes/Media}" ;;
  faststore) DEST_DIR="${PHOTOS_MOUNT:-/Volumes/Photos}" ;;
  *) echo "Unknown dest key: $DEST_KEY"; exit 1 ;;
esac
mkdir -p "$DEST_DIR"
rsync -ahv --progress "$SRC_DIR"/ "$DEST_DIR"/
echo "Restore complete → $DEST_DIR"
