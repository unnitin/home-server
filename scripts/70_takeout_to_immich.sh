#!/usr/bin/env bash
set -euo pipefail
# Usage: ./scripts/70_takeout_to_immich.sh /path/to/Takeout.zip
ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Usage: $0 </path/to/Takeout.zip>"; exit 1
fi

WORK="/tmp/takeout_work_$$"
mkdir -p "$WORK"
echo "Unzipping..."; /usr/bin/ditto -x -k "$ZIP" "$WORK"
# Move Google Photos content under a flat folder for upload
SRC="$WORK/Takeout/Google Photos"
if [[ ! -d "$SRC" ]]; then SRC="$WORK/Google Photos"; fi
if [[ ! -d "$SRC" ]]; then echo "Could not locate 'Google Photos' in archive"; exit 2; fi

UPLOAD_DIR="$WORK/upload"
mkdir -p "$UPLOAD_DIR"
# Copy only media files (common extensions)
find "$SRC" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.mp4" -o -iname "*.mov" \) -print0 | xargs -0 -I{} cp -n "{}" "$UPLOAD_DIR/"

echo "If 'immich-go' is installed, uploading now (else, files are in $UPLOAD_DIR):"
if command -v immich-go >/dev/null 2>&1; then
  if [[ -z "${IMMICH_SERVER:-}" || -z "${IMMICH_API_KEY:-}" ]]; then
    echo "Set IMMICH_SERVER and IMMICH_API_KEY env vars to auto-upload (e.g., http://localhost:2283)."
  else
    immich-go upload --server "$IMMICH_SERVER" --api-key "$IMMICH_API_KEY" "$UPLOAD_DIR"
  fi
fi
echo "Done. Upload dir: $UPLOAD_DIR"
