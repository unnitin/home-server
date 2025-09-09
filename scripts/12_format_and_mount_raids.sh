#!/usr/bin/env bash
# Format and mount AppleRAID sets to expected mountpoints.
# - SSD array name:   warmstore  -> /Volumes/Media
# - NVMe array name:  faststore  -> /Volumes/Photos
# - HDD/cold array:   coldstore  -> /Volumes/Archive
# Idempotent: if already APFS and mounted at the right place, it skips.

set -euo pipefail

ensure_dir() { [[ -d "$1" ]] || mkdir -p "$1"; }

# Return BSD device of the RAID set by name (e.g., disk8), or empty if not found.
bsd_for_raid_name() {
  local name="$1"
  # BRE-safe awk: no +/? — just extract fields by marker lines
  /usr/sbin/diskutil appleRAID list | /usr/bin/awk -v tgt="$name" '
    /^ *RAID Set Name:/ { nm=$0; sub(/^ *RAID Set Name:[ ]*/, "", nm); if (nm==tgt) in=1; else in=0; next }
    in && /^ *BSD Device Node:/ { dev=$0; sub(/^ *BSD Device Node:[ ]*/, "", dev); print dev; exit }
  '
}

# Return "APFS" if device contains APFS; else empty
is_apfs() {
  local devnode="$1"
  /usr/sbin/diskutil info "$devnode" 2>/dev/null | /usr/bin/awk '
    /^ *Type \(Bundle\):/ { t=$0; sub(/^ *Type \(Bundle\):[ ]*/, "", t); if (t=="apfs") {print "APFS"} }
  '
}

format_and_mount() {
  local raid_name="$1" vol_label="$2" mountpoint="$3"

  echo "-- Handling RAID '${raid_name}' -> ${mountpoint} (label: ${vol_label})"

  local bsd devnode
  bsd="$(bsd_for_raid_name "$raid_name" || true)"
  if [[ -z "$bsd" ]]; then
    echo "   (skip) RAID set '${raid_name}' not present. Continuing."
    return 0
  fi
  devnode="/dev/${bsd}"

  ensure_dir "$mountpoint"

  if [[ -n "$(is_apfs "$devnode")" ]]; then
    # Already APFS; ensure a volume with our label exists/mounted at mountpoint.
    local volDev
    volDev="$(/usr/sbin/diskutil list "$devnode" | /usr/bin/awk '
      /^ *APFS Volume Disk .* \(/ {
        m=$0; sub(/^.*: +/, "", m); print m
      }' | head -n1 | /usr/bin/awk '{print $1}' 2>/dev/null || true)"

    if [[ -n "${volDev:-}" ]]; then
      /usr/sbin/diskutil rename "/dev/${volDev}" "${vol_label}" >/dev/null 2>&1 || true
      /usr/sbin/diskutil mount "/dev/${volDev}" >/dev/null 2>&1 || true
      # If not mounted where we want, remount at the target point
      if ! mount | /usr/bin/grep -q "on ${mountpoint} "; then
        /usr/sbin/diskutil umount "/dev/${volDev}" >/dev/null 2>&1 || true
        ensure_dir "${mountpoint}"
        /usr/sbin/diskutil mount -mountPoint "${mountpoint}" "/dev/${volDev}" || true
      fi
      echo "   APFS volume present and mounted at ${mountpoint}."
      return 0
    fi
  fi

  # Not APFS yet (or no APFS volumes found): erase the RAID device as APFS
  echo "   Erasing ${devnode} as APFS (${vol_label}) and mounting at ${mountpoint}…"
  /usr/sbin/diskutil eraseVolume APFS "${vol_label}" "${devnode}"
  /usr/sbin/diskutil mount -mountPoint "${mountpoint}" "${devnode}" >/dev/null 2>&1 || true
  echo "   Done."
}

# Process the desired RAID->mount mappings without arrays (Bash 3.2-friendly)
while IFS='|' read -r name label mnt; do
  [[ -z "${name}" ]] && continue
  format_and_mount "$name" "$label" "$mnt"
done <<'MAP'
warmstore|Media|/Volumes/Media
faststore|Photos|/Volumes/Photos
coldstore|Archive|/Volumes/Archive
MAP

echo "✅ Format & mount complete."
