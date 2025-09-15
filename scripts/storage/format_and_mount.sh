#!/usr/bin/env bash
# Format and mount AppleRAID sets to expected mountpoints.
# - SSD array name:   warmstore  -> /Volumes/warmstore
# - NVMe array name:  faststore  -> /Volumes/faststore
# - HDD/cold array:   coldstore  -> /Volumes/coldstore
# Idempotent: if already APFS and mounted at the right place, it skips.

set -euo pipefail

ensure_dir() { [[ -d "$1" ]] || sudo mkdir -p "$1"; }

# Return BSD device of the RAID set by name (e.g., disk8), or empty if not found.
bsd_for_raid_name() {
  local name="$1"
  /usr/sbin/diskutil appleRAID list | /usr/bin/awk -v tgt="$name" '
    # if Name == tgt, mark that the next matching field belongs to it
    /^ *Name:/ {
      nm=$0
      sub(/^ *Name:[ ]*/,"",nm)
      if (nm==tgt) hit=1; else hit=0
      next
    }
    hit && /^ *Device Node:/ {
      dev=$0
      sub(/^ *Device Node:[ ]*/,"",dev)
      print dev
      exit
    }
  '
}

# Return "APFS" if device contains APFS; else empty
is_apfs() {
  local devnode="$1"
  /usr/sbin/diskutil info "$devnode" 2>/dev/null | /usr/bin/awk '
    /^ *Type \(Bundle\):/ { t=$0; sub(/^ *Type \(Bundle\):[ ]*/, "", t); if (t=="apfs") {print "APFS"} }
  '
}

# Note: Service coordination not needed since storage setup happens before services start

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
    # Already APFS; find the synthesized volume and remount at correct location
    echo "   Found existing APFS container. Locating volume..."
    
    # Find the synthesized container device (e.g., disk5 from disk4)
    local container_dev volume_dev current_mount raid_disk
    # Extract just the disk name (e.g., "disk4" from "/dev/disk4")
    raid_disk="${bsd}"
    
    container_dev="$(/usr/sbin/diskutil list | /usr/bin/awk -v raid="$raid_disk" '
      /synthesized/ { 
        # Found synthesized container, extract device name (e.g., disk5)
        sub(/.*\/dev\//, "", $0)
        sub(/[[:space:]].*/, "", $0)
        container = $0
      }
      /Physical Store/ && $0 ~ raid && container {
        # Found Physical Store line matching our RAID device
        print container
        exit
      }
    ')"
    
    if [[ -n "$container_dev" ]]; then
      # Find first APFS volume in the container
      volume_dev="$(/usr/sbin/diskutil list "$container_dev" | /usr/bin/awk '
        /^ *[0-9].*APFS Volume/ { print $NF; exit }
      ')"
      
      if [[ -n "$volume_dev" ]]; then
        echo "   Found APFS volume: $volume_dev"
        
        # Check current mount point
        current_mount="$(mount | /usr/bin/grep "/dev/$volume_dev" | /usr/bin/awk '{print $3}' || true)"
        
        if [[ "$current_mount" == "$mountpoint" ]]; then
          echo "   Already mounted at correct location: $mountpoint"
          return 0
        elif [[ -n "$current_mount" ]]; then
          echo "   Remounting from $current_mount to $mountpoint..."
          /usr/sbin/diskutil umount "/dev/$volume_dev" >/dev/null 2>&1 || true
        fi
        
        # Mount at correct location
        ensure_dir "$mountpoint"
        /usr/sbin/diskutil mount -mountPoint "$mountpoint" "/dev/$volume_dev" || {
          echo "   ❌ Failed to mount $volume_dev at $mountpoint"
          return 1
        }
        
        echo "   ✅ APFS volume mounted at $mountpoint"
        return 0
      fi
    fi
    
    echo "   ⚠️ Could not locate APFS volume, will reformat..."
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
warmstore|warmstore|/Volumes/warmstore
faststore|faststore|/Volumes/faststore
coldstore|coldstore|/Volumes/coldstore
MAP

# Validate all mount operations completed successfully
validate_mount_setup() {
  local all_good=true
  
  echo
  echo "=== Validating Mount Setup ==="
  
  for mount_info in "warmstore:/Volumes/warmstore:warmstore" "faststore:/Volumes/faststore:faststore" "coldstore:/Volumes/coldstore:coldstore"; do
    IFS=':' read -r purpose mountpoint expected_tier <<< "$mount_info"
    
    if [[ -n "$(bsd_for_raid_name "$expected_tier" || true)" ]]; then
      # RAID exists, check if properly mounted
      if df -h "$mountpoint" >/dev/null 2>&1; then
        local size usage
        size=$(df -h "$mountpoint" | tail -n1 | awk '{print $2}')
        usage=$(df -h "$mountpoint" | tail -n1 | awk '{print $5}')
        echo "✅ $purpose: $mountpoint ($size, $usage used)"
        
        # Test write permissions
        if touch "$mountpoint/.mount_test_$$" 2>/dev/null; then
          rm -f "$mountpoint/.mount_test_$$"
          echo "   ✅ Write permissions OK"
        else
          echo "   ❌ Write permissions FAILED"
          all_good=false
        fi
      else
        echo "❌ $purpose: $mountpoint (NOT MOUNTED)"
        all_good=false
      fi
    else
      echo "⚪ $purpose: $expected_tier (RAID not present, skipping)"
    fi
  done
  
  if $all_good; then
    echo "✅ All available storage properly mounted and accessible!"
  else
    echo "❌ Some mount issues detected. Check logs above."
    return 1
  fi
}

echo "✅ Format & mount complete."
validate_mount_setup
