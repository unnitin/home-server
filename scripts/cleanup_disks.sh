#!/usr/bin/env bash
# Destructively clean disks and remove any AppleRAID sets that include them.
# Usage:
#   RAID_I_UNDERSTAND_DATA_LOSS=1 scripts/cleanup_disks.sh disk6 [disk7 ...]
#
# Notes:
# - This will DELETE any AppleRAID set that includes the specified disks.
# - It then wipes the disks and reinitializes a fresh GUID map with a tiny APFS volume.
# - Pass WHOLE disk identifiers (e.g., disk6), not slices (e.g., disk6s2).
# - Run on macOS (uses diskutil/gpt).

set -euo pipefail

if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
  echo "Refusing: set RAID_I_UNDERSTAND_DATA_LOSS=1 to acknowledge this is DESTRUCTIVE."
  exit 2
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: RAID_I_UNDERSTAND_DATA_LOSS=1 $0 disk6 [disk7 ...]"
  exit 1
fi

# Validate arguments are whole disk IDs
for d in "$@"; do
  if [[ ! "$d" =~ ^disk[0-9]+$ ]]; then
    echo "❌ Invalid argument '$d'. Use WHOLE disks like 'disk6', not 'disk6s2'."
    exit 1
  fi
done

echo "=== AppleRAID cleanup (DESTRUCTIVE) ==="
date

# Build a robust map of RAID Set UUID -> member disks (normalized to whole disk)
echo "[1/3] Inspecting AppleRAID sets..."
LISTING="$(sudo diskutil appleRAID list || true)"

# For each requested disk, find & delete any set that includes it
delete_sets_for_disk() {
  local target="$1"
  # Find the first set that includes target; delete; repeat until none remain
  while : ; do
    local uuid
    uuid="$(printf "%s\n" "$LISTING" | /usr/bin/awk -v tgt="$target" '
      /^RAID Set UUID:/ {u=$3}
      /^Members:/       {inmem=1; next}
      /^=+/             {inmem=0}
      inmem {
        # extract first disk token; normalize diskNsM -> diskN
        match($0, /disk[0-9]+(s[0-9]+)?/, m)
        if (m[0] != "") {
          gsub(/s[0-9]+$/, "", m[0])
          if (m[0] == tgt) { print u; exit }
        }
      }')"
    [[ -z "$uuid" ]] && break
    echo "→ Deleting AppleRAID set $uuid (contains $target)..."
    sudo diskutil appleRAID delete "$uuid" || true
    # refresh listing in case there are multiple sets
    LISTING="$(sudo diskutil appleRAID list || true)"
  done
}

for d in "$@"; do
  delete_sets_for_disk "$d"
done

echo "[2/3] Wiping partition maps (gpt) and reinitializing disks..."
for d in "$@"; do
  dev="/dev/$d"
  echo "→ Cleaning $dev"
  sudo diskutil unmountDisk force "$dev" || true
  sudo gpt destroy -f "$dev" || true
  # Fresh GUID map + tiny APFS volume named 'temp' just to fully initialize the device
  sudo diskutil eraseDisk APFS temp GPT "$dev"
done

echo "[3/3] Verifying results..."
sudo diskutil list | grep -E "(/dev/($(printf '%s|' "$@" | sed 's/|$//')))"

echo "✅ Cleanup complete. Disks ready for RAID create scripts."
echo
echo "Next steps (example for 2-disk SSD mirror):"
echo "  export RAID_I_UNDERSTAND_DATA_LOSS=1"
echo "  export SSD_DISKS=\"${1:-diskX} ${2:-diskY}\""
echo "  scripts/10_create_raid10_ssd.sh && scripts/12_format_and_mount_raids.sh"
