#!/usr/bin/env bash
# Destructively clean disks and remove any AppleRAID sets that include them.
# Usage:
#   RAID_I_UNDERSTAND_DATA_LOSS=1 scripts/cleanup_disks.sh disk6 [disk7 ...]

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
echo "[1/3] Inspecting AppleRAID sets..."

LISTING="$(sudo diskutil appleRAID list || true)"

# Delete any set that includes target disk(s).
delete_sets_for_disk() {
  local target="$1"
  while : ; do
    # BRE-safe extract: first token like diskNNN (ignores slice suffix)
    local uuid
    uuid="$(printf "%s\n" "$LISTING" | /usr/bin/awk -v tgt="$target" '
      /^RAID Set UUID:/ {u=$3}
      /^Members:/       {inmem=1; next}
      /^=+/             {inmem=0}
      inmem {
        # find first disk token: disk + digits (no + or ?)
        if (match($0, /disk[0-9][0-9]*/)) {
          root=substr($0, RSTART, RLENGTH)   # e.g., disk6
          if (root == tgt) { print u; exit }
        }
      }')"
    [[ -z "$uuid" ]] && break
    echo "→ Deleting AppleRAID set $uuid (contains $target)..."
    sudo diskutil appleRAID delete "$uuid" || true
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
  # Fresh GUID map + tiny APFS volume named 'temp'
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
