#!/usr/bin/env bash
#
# Google Photos Takeout -> Immich helper
#
# Features:
#  - Unzips multiple Google Takeout .zip files into a staging directory
#  - Normalizes the folder structure and collects media into a unified tree
#  - Optionally preserves album structure by building album folders (via symlinks)
#  - Uploads to Immich using either:
#       * immich-go (preferred) if installed
#       * immich-go Docker container if Docker is available
#  - Produces a summary report of files discovered and uploaded
#
# Requirements:
#   - IMMICH_SERVER        e.g., http://localhost:2283
#   - IMMICH_API_KEY       Create in Immich Web → Account → API Keys
#
# Usage:
#   export IMMICH_SERVER="http://localhost:2283"
#   export IMMICH_API_KEY="..."
#   ./scripts/70_takeout_to_immich.sh -i /path/to/TakeoutZips -w /tmp/immich-import [--no-unzip]
#
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }
info(){ echo "==> $*"; }
warn(){ echo "⚠️  $*" >&2; }

if [[ "${IMMICH_SERVER:-}" == "" || "${IMMICH_API_KEY:-}" == "" ]]; then
  die "IMMICH_SERVER and IMMICH_API_KEY env vars must be set"
fi

INPUT_DIR=""
WORK_DIR=""
NO_UNZIP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input) INPUT_DIR="${2:-}"; shift 2 ;;
    -w|--work)  WORK_DIR="${2:-}";  shift 2 ;;
    --no-unzip) NO_UNZIP=1; shift ;;
    -h|--help)
      sed -n '1,80p' "$0"; exit 0 ;;
    *)
      die "Unknown arg: $1 (use -h for help)"
  esac
done

[[ -n "$INPUT_DIR" ]] || die "Missing -i/--input directory (folder with Google Takeout zips OR extracted Takeout)"
[[ -n "$WORK_DIR"  ]] || die "Missing -w/--work staging directory"

mkdir -p "$WORK_DIR"
STAGING="$WORK_DIR/staging"
MEDIA_ROOT="$WORK_DIR/media"
ALBUMS_ROOT="$WORK_DIR/albums"

mkdir -p "$STAGING" "$MEDIA_ROOT" "$ALBUMS_ROOT"

unzip_if_needed() {
  shopt -s nullglob
  local zips=("$INPUT_DIR"/*.zip)
  if (( ${#zips[@]} == 0 )); then
    warn "No .zip files found; assuming $INPUT_DIR is already extracted."
    return 0
  fi
  info "Unzipping ${#zips[@]} Takeout archive(s) into $STAGING ..."
  for z in "${zips[@]}"; do
    info "Unzipping: $(basename "$z")"
    unzip -qq -o "$z" -d "$STAGING"
  done
}

discover_roots() {
  # Google Takeout usually creates: Takeout/Google Photos/<AlbumName> or just Google Photos/<AlbumName>
  local roots=()
  if [[ -d "$STAGING/Takeout/Google Photos" ]]; then
    roots+=("$STAGING/Takeout/Google Photos")
  fi
  if [[ -d "$STAGING/Google Photos" ]]; then
    roots+=("$STAGING/Google Photos")
  fi
  if [[ -d "$INPUT_DIR/Takeout/Google Photos" ]]; then
    roots+=("$INPUT_DIR/Takeout/Google Photos")
  fi
  if [[ -d "$INPUT_DIR/Google Photos" ]]; then
    roots+=("$INPUT_DIR/Google Photos")
  fi

  if (( ${#roots[@]} == 0 )); then
    warn "Could not locate 'Google Photos' root in extracted data; using $INPUT_DIR directly."
    roots+=("$INPUT_DIR")
  fi

  printf "%s\n" "${roots[@]}"
}

collect_media() {
  # Copy (not move) media files into MEDIA_ROOT, keeping original filenames and a unique prefix if collisions occur.
  # Supported extensions
  local exts="jpg jpeg png heic heif gif webp mp4 mov 3gp m4v avi mpg mpeg"
  local count=0
  while IFS= read -r -d '' f; do
    local base="$(basename "$f")"
    local dest="$MEDIA_ROOT/$base"
    if [[ -e "$dest" ]]; then
      local stem="${base%.*}"; local ext="${base##*.}"
      local i=1
      while [[ -e "$MEDIA_ROOT/${stem}__dup${i}.${ext}" ]]; do ((i++)); done
      dest="$MEDIA_ROOT/${stem}__dup${i}.${ext}"
    end
    cp -p "$f" "$dest"
    ((count++))
  done < <(find "$@" -type f \( $(printf -- '-iname "*.%s" -o ' $exts | sed 's/ -o $//') \) -print0)

  echo "$count"
}

build_album_links() {
  # Create "albums" tree containing symlinks back to MEDIA_ROOT, matching Google Takeout folder album names.
  local roots=("$@")
  local made=0
  shopt -s nullglob
  for root in "${roots[@]}"; do
    for dir in "$root"/*/ ; do
      [[ -d "$dir" ]] || continue
      local name="$(basename "$dir")"
      # skip system folders from Takeout like "Photos from 2016" if empty
      mkdir -p "$ALBUMS_ROOT/$name"
      # Link media files in this folder to the album dir
      while IFS= read -r -d '' mf; do
        local base="$(basename "$mf")"
        # Find the canonical copy in MEDIA_ROOT (original or deduped)
        local candidate="$MEDIA_ROOT/$base"
        if [[ -e "$candidate" ]]; then
          ln -s "../../media/$base" "$ALBUMS_ROOT/$name/$base" 2>/dev/null || true
          ((made++))
        fi
      done < <(find "$dir" -maxdepth 1 -type f -regex '.*\.\(jpg\|jpeg\|png\|heic\|heif\|gif\|webp\|mp4\|mov\|3gp\|m4v\|avi\|mpg\|mpeg\)$' -print0)
    done
  done
  echo "$made"
}

upload_with_immich_go() {
  local path="$1"
  local args=(
    "--server" "$IMMICH_SERVER"
    "--api-key" "$IMMICH_API_KEY"
    "upload"
    "--path" "$path"
    "--concurrency" "4"
    "--ignore-duplicates"
  )
  if command -v immich-go >/dev/null 2>&1; then
    info "Uploading with immich-go (binary) from $path ..."
    immich-go "${args[@]}"
    return $?
  fi

  if command -v docker >/dev/null 2>&1; then
    info "Uploading with immich-go (Docker) from $path ..."
    docker run --rm \
      -e IMMICH_SERVER="$IMMICH_SERVER" \
      -e IMMICH_API_KEY="$IMMICH_API_KEY" \
      -v "$path":/input:ro \
      ghcr.io/immich-app/immich-go:latest \
      upload --server "$IMMICH_SERVER" --api-key "$IMMICH_API_KEY" --path /input --concurrency 4 --ignore-duplicates
    return $?
  fi

  warn "immich-go (binary or Docker) not found. Skipping automatic upload."
  return 127
}

main() {
  if [[ $NO_UNZIP -eq 0 ]]; then
    unzip_if_needed
  else
    info "--no-unzip set; using $INPUT_DIR as-is"
    STAGING="$INPUT_DIR"
  fi

  mapfile -t roots < <(discover_roots)
  info "Detected roots:"
  printf "  - %s\n" "${roots[@]}"

  info "Collecting media into $MEDIA_ROOT ..."
  local collected
  collected=$(collect_media "${roots[@]}")
  info "Collected $collected files."

  info "Building album link tree under $ALBUMS_ROOT ..."
  local linked
  linked=$(build_album_links "${roots[@]}")
  info "Created $linked album symlinks."

  info "Uploading 'media' to Immich (this may take a while)..."
  if upload_with_immich_go "$MEDIA_ROOT"; then
    info "Upload attempt completed."
  else
    warn "Automatic upload skipped/failed. You can upload manually via Immich Web or install immich-go."
  fi

  cat <<EOF

Summary:
  Work dir:    $WORK_DIR
  Media root:  $MEDIA_ROOT  (collected originals; deduplicated names)
  Albums root: $ALBUMS_ROOT (symlinks mirroring Google albums)

Next steps:
  - If upload was skipped, install 'immich-go' or run the Docker command printed above.
  - In Immich, let background jobs (face/object indexing) finish; progress appears in Admin UI.
EOF
}

main "$@"
