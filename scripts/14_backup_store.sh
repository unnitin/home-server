#!/usr/bin/env bash
# Non-destructive backup from a source store (warmstore/faststore paths) to ANY mounted target directory.
# Works with single external HDDs (no RAID), NAS mounts, etc.
# Usage examples:
#   ./scripts/14_backup_store.sh warmstore /Volumes/MyBackupDrive/MediaBackup
#   ./scripts/14_backup_store.sh faststore  /Volumes/MyBackupDrive/PhotosBackup
#
# Sources map:
#   warmstore -> ${MEDIA_MOUNT:-/Volumes/Media}
#   faststore -> ${PHOTOS_MOUNT:-/Volumes/Photos}
#
set -euo pipefail

SRC_KEY="${1:-}"
DEST_DIR="${2:-}"

if [[ -z "$SRC_KEY" || -z "$DEST_DIR" ]]; then
  echo "Usage: $0 <warmstore|faststore> <destination-dir>"
  exit 1
fi

case "$SRC_KEY" in
  warmstore) SRC_DIR="${MEDIA_MOUNT:-/Volumes/Media}" ;;
  faststore) SRC_DIR="${PHOTOS_MOUNT:-/Volumes/Photos}" ;;
  *) echo "Unknown source key: $SRC_KEY (use warmstore or faststore)"; exit 1 ;;
esac

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Source dir not found: $SRC_DIR"; exit 1
fi

mkdir -p "$DEST_DIR"

echo "== Backup =="
echo "From: $SRC_DIR"
echo "To:   $DEST_DIR"
echo

# Show free space
df -h "$DEST_DIR" || true

# rsync flags:
# -a: archive (preserve perms, times, symlinks)
# -h: human-readable
# -v: verbose
# --delete-after: (optional) remove files on dest that were removed from source (commented by default)
# --progress: show progress
RSYNC_FLAGS=(-ahv --progress)

# If you want exact mirror behavior, uncomment the next line:
# RSYNC_FLAGS+=("--delete-after")

rsync "${RSYNC_FLAGS[@]}" "$SRC_DIR"/ "$DEST_DIR"/

echo
echo "Backup complete."
