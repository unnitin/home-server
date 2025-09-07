#!/usr/bin/env bash
set -euo pipefail

CPU="${COLIMA_CPU:-4}"
MEM="${COLIMA_MEM:-6}"
DISK="${COLIMA_DISK:-60}"   # desired minimum; existing VMs won't be shrunk

PROFILE="$HOME/.colima/_lima/colima/colima.yaml"

# If a profile exists and requests a smaller disk than desired, bump it (prevents shrink attempts)
if [[ -f "$PROFILE" ]]; then
  CUR_CFG=$(awk -F': *' '/^disk:/{print $2}' "$PROFILE" | head -n1 || true)
  if [[ -n "${CUR_CFG:-}" && "$CUR_CFG" =~ ^[0-9]+$ ]] && (( CUR_CFG < DISK )); then
    # Only grow the requested size in the config; never shrink
    /usr/bin/sed -i '' "s/^disk:\s*[0-9][0-9]*/disk: ${DISK}/" "$PROFILE" || true
  fi
fi

# Helper: parse current VM disk size (GiB) from status
current_vm_disk_gib() {
  colima status 2>/dev/null | awk -F': ' '/Disk/{print $2}' | awk '{print $1}' || true
}

if colima status >/dev/null 2>&1; then
  echo "Colima instance exists."
  CUR_VM="$(current_vm_disk_gib || true)"
  if [[ -n "${CUR_VM:-}" && "$DISK" =~ ^[0-9]+$ ]] && (( DISK > CUR_VM )); then
    echo "Growing VM disk ${CUR_VM}GiB → ${DISK}GiB"
    colima stop
    colima start --disk "$DISK"
  else
    echo "Starting without resize (VM disk: ${CUR_VM:-unknown} GiB)"
    colima start
  fi
else
  echo "Creating new Colima instance: cpu=${CPU} mem=${MEM}G disk=${DISK}G"
  colima start --cpu "$CPU" --memory "$MEM" --disk "$DISK" --arch aarch64
fi

docker context use colima
unset DOCKER_HOST
colima status || true
docker info | grep -E 'Context:|Server Version' || true
echo "✅ Colima ready (docker context = colima)."
