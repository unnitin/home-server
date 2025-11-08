#!/usr/bin/env bash
set -euo pipefail
# Usage: ./scripts/services/import_takeout.sh /path/to/Takeout.zip
# Optional env: IMMICH_SERVER (e.g., http://localhost:2283), IMMICH_API_KEY
#
# NOTE: For enhanced Google Photos takeout import with full metadata preservation,
# use the new enhanced solution: scripts/takeout/enhanced_takeout_import.sh

ZIP="${1:-}"
if [[ -z "$ZIP" || ! -f "$ZIP" ]]; then
  echo "Usage: $0 </path/to/Takeout.zip>"
  echo ""
  echo "For enhanced Google Photos takeout import with full metadata preservation:"
  echo "  cd scripts/takeout && ./enhanced_takeout_import.sh --help"
  exit 1
fi

WORK="$(mktemp -d /tmp/takeout.XXXXXX)"
echo "Working in $WORK"

echo "Unzipping..."
/usr/bin/ditto -x -k "$ZIP" "$WORK"

SRC="$WORK/Takeout/Google Photos"
if [[ ! -d "$SRC" ]]; then SRC="$WORK/Google Photos"; fi
if [[ ! -d "$SRC" ]]; then
  echo "Could not find 'Google Photos' directory in Takeout archive"; exit 2
fi

UPLOAD_DIR="$WORK/upload"
mkdir -p "$UPLOAD_DIR"

# Copy common photo/video formats (skip JSON sidecars)
find "$SRC" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.heic" -o -iname "*.gif" -o -iname "*.mp4" -o -iname "*.mov" -o -iname "*.m4v" \) -print0 \
  | xargs -0 -I{} cp -n "{}" "$UPLOAD_DIR/"

COUNT=$(find "$UPLOAD_DIR" -type f | wc -l | tr -d ' ')
echo "Prepared $COUNT media files for upload in: $UPLOAD_DIR"

if command -v immich-go >/dev/null 2>&1; then
  if [[ -n "${IMMICH_SERVER:-}" && -n "${IMMICH_API_KEY:-}" ]]; then
    echo "Uploading to Immich at $IMMICH_SERVER via immich-go"
    immich-go upload --server "$IMMICH_SERVER" --api-key "$IMMICH_API_KEY" "$UPLOAD_DIR"
  else
    echo "Set IMMICH_SERVER and IMMICH_API_KEY to auto-upload. Skipping upload."
  fi
else
  echo "Tip: install https://github.com/immich-app/immich-go for fast CLI uploads."
fi

echo "Done. You can manually upload from: $UPLOAD_DIR"
