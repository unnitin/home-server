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
  diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {f=1}
    f && /Device Node/ {print $3; exit}
  '
}

delete_raid_by_name(){
  local name="$1"
  local dev uuid
  dev="$(raid_device_for "$name")" || true
  uuid="$(diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {f=1}
    f && /UUID/ {print $3; exit}
  ')" || true
  if [[ -n "${uuid:-}" ]]; then
    echo "Deleting existing RAID '$name' ($uuid)"
    diskutil unmountDisk force "$dev" || true
    diskutil appleRAID delete "$uuid" || true
    sleep 2
  fi
}

create_mirror(){
  local name="$1" d1="$2" d2="$3"
  diskutil appleRAID create mirror "$name" APFS "$d1" "$d2"
  sleep 2
  raid_device_for "$name"
}

create_stripe_of_mirrors(){
  local name="$1" m1="$2" m2="$3"
  diskutil appleRAID create stripe "$name" APFS "$m1" "$m2"
  sleep 2
  raid_device_for "$name"
}

format_and_mount(){
  local dev="$1" volname="$2" mount="$3"
  [[ -n "$dev" ]] || { echo "No device to format"; exit 4; }
  diskutil eraseVolume APFS "$volname" "$dev"
  mkdir -p "$mount"
  diskutil mount "$dev" || true
}
