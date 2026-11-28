#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

MEDIA_MOUNT="${MEDIA_MOUNT:-$(diag_tier_mount warmstore /Volumes/warmstore)}"
PHOTOS_MOUNT="${PHOTOS_MOUNT:-$(diag_tier_mount faststore /Volumes/faststore)}"
ARCHIVE_MOUNT="${ARCHIVE_MOUNT:-$(diag_tier_mount coldstore /Volumes/coldstore)}"

# Mounted means diskutil says a volume is there: an empty mount-point folder
# isn't storage, and a write test in one would land on the internal disk (D22)
section "Mount points"
for m in "$MEDIA_MOUNT" "$PHOTOS_MOUNT" "$ARCHIVE_MOUNT"; do
  if diag_is_mounted "$m"; then ok "Mounted: $m"
  elif [ -d "$m" ]; then warn "Not mounted (an empty mount-point folder): $m"
  else warn "Not mounted: $m"; fi
done

section "Write test (touch)"
for m in "$MEDIA_MOUNT" "$PHOTOS_MOUNT"; do
  if ! diag_is_mounted "$m"; then
    warn "Not mounted, not tested: $m"
  elif touch "$m/.diag_write_test" 2>/dev/null; then
    ok "Writable: $m"
    rm -f "$m/.diag_write_test"
  else
    warn "Not writable: $m"
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
