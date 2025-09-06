#!/usr/bin/env bash
set -euo pipefail
SRC_KEY="${1:-}"; DEST_DIR="${2:-}"
[[ -n "$SRC_KEY" && -n "$DEST_DIR" ]] || { echo "Usage: $0 <warmstore|faststore> <destination-dir>"; exit 1; }

case "$SRC_KEY" in
  warmstore) SRC_DIR="${MEDIA_MOUNT:-/Volumes/Media}" ;;
  faststore) SRC_DIR="${PHOTOS_MOUNT:-/Volumes/Photos}" ;;
  *) echo "Unknown source key: $SRC_KEY"; exit 1 ;;
esac

[[ -d "$SRC_DIR" ]] || { echo "Source not found: $SRC_DIR"; exit 2; }
mkdir -p "$DEST_DIR"

rsync -ahv --progress "$SRC_DIR"/ "$DEST_DIR"/
echo "Backup complete → $DEST_DIR"
