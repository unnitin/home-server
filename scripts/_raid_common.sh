# Common functions for AppleRAID operations
require_confirm() {
  if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
    echo "DRY RUN: Set RAID_I_UNDERSTAND_DATA_LOSS=1 to proceed with destructive RAID changes."
    exit 2
  fi
}

parse_disks() {
  local varname="$1"
  local value="${!varname:-}"
  if [[ -z "$value" ]]; then
    echo "ERROR: $varname not set. Example: export %s=\"disk4 disk5 disk6 disk7\"" "$varname" >&2
    exit 1
  fi
  read -r -a DISKS <<< "$value"
  if [[ "${#DISKS[@]}" -ne 4 ]]; then
    echo "ERROR: Exactly 4 disks required in $varname (got ${#DISKS[@]})." >&2
    exit 1
  fi
  # Ensure unique
  if [[ "$(printf "%s\n" "${DISKS[@]}" | sort | uniq | wc -l | tr -d ' ')" -ne 4 ]]; then
    echo "ERROR: Duplicated disk identifiers in $varname." >&2
    exit 1
  fi
  for d in "${DISKS[@]}"; do
    if ! diskutil info "$d" >/dev/null 2>&1; then
      echo "ERROR: $d is not a valid disk device." >&2
      exit 1
    fi
  done
}

destroy_partitions() {
  for d in "${DISKS[@]}"; do
    echo "Erasing partition map on /dev/$d ..."
    sudo diskutil eraseDisk free none GPT "/dev/$d"
  done
}

create_mirror() {
  local name="$1" ; shift
  local d1="$1" ; local d2="$2"
  echo "Creating AppleRAID mirror '$name' on $d1 and $d2 ..."
  # Create an APFS-formatted mirror set
  # diskutil returns a UUID; we will resolve to device node via 'diskutil appleRAID list'
  local uuid
  uuid=$(sudo diskutil appleRAID create mirror "$name" APFS "$d1" "$d2" | awk '/UUID/ {print $NF}')
  sleep 3
  # Find the Device Node for the newly created set
  local dev
  dev=$(diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {found=1}
    found && $0 ~ /Device Node/ {print $3; exit}
  ')
  if [[ -z "$dev" ]]; then
    echo "ERROR: Could not resolve device node for mirror $name" >&2
    exit 1
  fi
  echo "$dev"
}

create_stripe_from_mirrors() {
  local name="$1" ; shift
  local m1="$1" ; local m2="$2"
  echo "Creating AppleRAID stripe '$name' across $m1 and $m2 ..."
  sudo diskutil appleRAID create stripe "$name" APFS "$m1" "$m2"
}

post_create_mount_and_prepare() {
  local vol_name="$1"
  local mount_point="$2"
  # The stripe creation above already formats APFS with name $vol_name,
  # but ensure it is mounted and create the mount dir symlink if needed.
  echo "Ensuring $mount_point exists..."
  sudo mkdir -p "$mount_point"
  echo "Created/verified mount point: $mount_point"
}


# ---- Teardown helpers ----
find_raid_device_by_name() {
  local name="$1"
  # Return the Device Node (e.g., diskX) for an AppleRAID set with the given name
  diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {found=1}
    found && /Device Node/ {print $3; exit}
  '
}

delete_raid_by_name() {
  local name="$1"
  local dev
  dev="$(find_raid_device_by_name "$name")"
  if [[ -z "$dev" ]]; then
    echo "No AppleRAID set named '$name' found; nothing to delete."
    return 0
  fi
  local uuid
  uuid="$(diskutil appleRAID list | awk -v n="$name" '
    $0 ~ "RAID Set Name: " n {found=1}
    found && /UUID/ {print $3; exit}
  ')"
  if [[ -z "$uuid" ]]; then
    echo "Could not locate UUID for set '$name' (dev=$dev). Aborting delete." >&2
    return 1
  fi
  echo "Deleting AppleRAID set '$name' (UUID=$uuid, Device=$dev)..."
  sudo diskutil unmountDisk force "$dev" || true
  sudo diskutil appleRAID delete "$uuid"
}
