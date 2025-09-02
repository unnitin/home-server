#!/usr/bin/env bash
# Restore from ANY directory (external HDD, NAS, etc.) back into warmstore or faststore.
# Usage:
#   ./scripts/15_restore_store.sh /Volumes/MyBackupDrive/MediaBackup warmstore
#   ./scripts/15_restore_store.sh /Volumes/MyBackupDrive/PhotosBackup faststore
#
set -euo pipefail

SRC_DIR="${1:-}"
DEST_KEY="${2:-}"

if [[ -z "$SRC_DIR" || -z "$DEST_KEY" ]]; then
  echo "Usage: $0 <source-dir> <warmstore|faststore>"
  exit 1
fi

case "$DEST_KEY" in
  warmstore) DEST_DIR="${MEDIA_MOUNT:-/Volumes/Media}" ;;
  faststore) DEST_DIR="${PHOTOS_MOUNT:-/Volumes/Photos}" ;;
  *) echo "Unknown dest key: $DEST_KEY (use warmstore or faststore)"; exit 1 ;;
esac

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source dir not found: $SRC_DIR"; exit 1
fi
mkdir -p "$DEST_DIR"

echo "== Restore =="
echo "From: $SRC_DIR"
echo "To:   $DEST_DIR"
echo

df -h "$DEST_DIR" || true

RSYNC_FLAGS=(-ahv --progress)
# If you want exact mirror behavior, uncomment the next line:
# RSYNC_FLAGS+=("--delete-after")

rsync "${RSYNC_FLAGS[@]}" "$SRC_DIR"/ "$DEST_DIR"/

echo
echo "Restore complete."
