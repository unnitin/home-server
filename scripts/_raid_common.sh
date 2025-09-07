#!/usr/bin/env bash
set -euo pipefail

require_guard(){
  if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
    echo "Refusing: set RAID_I_UNDERSTAND_DATA_LOSS=1"; exit 2
  fi
}

parse_disks(){
  local var="$1"; local raw="${!var:-}"
  [[ -n "$raw" ]] || { echo "Missing $var (e.g., 'disk4 disk5 [disk6 disk7]')"; exit 3; }
  read -r -a DISKS <<< "$raw"
}

raid_device_for(){
  local name="$1"
  sudo diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {f=1}
    f && /Device Node/ {print $3; exit}
  '
}

delete_raid_by_name(){
  local name="$1"
  local dev uuid
  dev="$(raid_device_for "$name")" || true
  uuid="$(sudo diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {f=1}
    f && /UUID/ {print $3; exit}
  ')" || true
  if [[ -n "${uuid:-}" ]]; then
    echo "Deleting existing RAID '$name' ($uuid)"
    sudo diskutil unmountDisk force "$dev" || true
    sudo diskutil appleRAID delete "$uuid" || true
    sleep 2
  fi
}

# Remove any AppleRAID set that contains one of the given whole-disk IDs (destructive)
delete_raids_containing_disks() {
  local disks=("$@")
  local listing pairs
  listing="$(sudo diskutil appleRAID list)"
  pairs="$(awk '
    /RAID Set UUID:/ {uuid=$3}
    /Members:/ {inmem=1; next}
    inmem && /disk[0-9]+/ {print uuid, $NF}
    /^=+$/ {inmem=0}
  ' <<< "$listing")"

  for d in "${disks[@]}"; do
    [[ "$d" =~ ^disk[0-9]+$ ]] || continue
    while read -r uuid member; do
      [[ -z "$uuid" || -z "$member" ]] && continue
      if [[ "$member" == "$d" ]]; then
        echo "Deleting existing AppleRAID set $uuid because it includes $d"
        sudo diskutil appleRAID delete "$uuid" || true
      fi
    done <<< "$pairs"
  done
}

create_mirror(){
  local name="$1" d1="$2" d2="$3"
  sudo diskutil appleRAID create mirror "$name" APFS "$d1" "$d2"
  sleep 2
  raid_device_for "$name"
}

create_stripe_of_mirrors(){
  local name="$1" m1="$2" m2="$3"
  sudo diskutil appleRAID create stripe "$name" APFS "$m1" "$m2"
  sleep 2
  raid_device_for "$name"
}

format_and_mount(){
  local dev="$1" volname="$2" mount="$3"
  [[ -n "$dev" ]] || { echo "No device to format"; exit 4; }
  sudo diskutil eraseVolume APFS "$volname" "$dev"
  sudo mkdir -p "$mount"
  sudo diskutil mount "$dev" || true
}
