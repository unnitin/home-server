#!/usr/bin/env bash
# Pre-clean disks before RAID creation (DESTRUCTIVE).
# Runs only if:
#   RAID_I_UNDERSTAND_DATA_LOSS=1  (ack destructive)
#   CLEAN_BEFORE_RAID=1            (opt-in)
# It will call scripts/cleanup_disks.sh for each disk set env that is present:
#   SSD_DISKS / NVME_DISKS / COLD_DISKS (whole disks only, e.g., "disk6 disk7")

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLEANER="$ROOT_DIR/scripts/cleanup_disks.sh"

if [[ "${CLEAN_BEFORE_RAID:-0}" != "1" ]]; then
  echo "[preclean] Skipping (CLEAN_BEFORE_RAID is not 1)."
  exit 0
fi

if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
  echo "[preclean] Refusing: set RAID_I_UNDERSTAND_DATA_LOSS=1 (DESTRUCTIVE)."
  exit 2
fi

[[ -x "$CLEANER" ]] || { echo "[preclean] missing $CLEANER"; exit 3; }

run_clean() {
  local label="$1"; shift
  local disks=("$@")
  [[ ${#disks[@]} -gt 0 ]] || return 0

  echo "[preclean] $label: ${disks[*]}"
  # Validate whole disks only
  for d in "${disks[@]}"; do
    [[ "$d" =~ ^disk[0-9]+$ ]] || { echo "[preclean] '$d' is not a whole disk id (e.g., disk6)"; exit 1; }
  done

  RAID_I_UNDERSTAND_DATA_LOSS=1 "$CLEANER" "${disks[@]}"
}

# Parse env into arrays safely
read -r -a _SSD  <<< "${SSD_DISKS:-}"
read -r -a _NVME <<< "${NVME_DISKS:-}"
read -r -a _COLD <<< "${COLD_DISKS:-}"

run_clean "SSD_DISKS"   "${_SSD[@]}"
run_clean "NVME_DISKS"  "${_NVME[@]}"
run_clean "COLD_DISKS"  "${_COLD[@]}"

echo "[preclean] Done."
