#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

MEDIA_MOUNT="${MEDIA_MOUNT:-/Volumes/warmstore}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-/Volumes/faststore}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-/Volumes/Archive}"

section "Mount points"
for m in "$MEDIA_MOUNT" "$PHOTOS_MOUNT" "$ARCHIVE_MOUNT"; do
  if [ -d "$m" ]; then ok "Exists: $m"; else warn "Missing: $m"; fi
done

section "Write test (touch)"
for m in "$MEDIA_MOUNT" "$PHOTOS_MOUNT"; do
  if [ -d "$m" ] && touch "$m/.diag_write_test" 2>/dev/null; then
    ok "Writable: $m"
    rm -f "$m/.diag_write_test"
  else
    warn "Not writable or missing: $m"
  fi
done

section "AppleRAID (faststore/warmstore)"
if command -v diskutil >/dev/null 2>&1; then
  if diskutil appleRAID list >/dev/null 2>&1; then
    ok "diskutil appleRAID list OK"
    diskutil appleRAID list | sed -n '1,200p' | sed -e "s/^/  /"
  else
    warn "No AppleRAID sets found"
  fi
else
  warn "diskutil not available"
fi

print_summary
