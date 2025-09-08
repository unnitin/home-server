#!/usr/bin/env bash
set -euo pipefail

# Block running as root; colima/docker contexts are per-user.
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Do not run this script with sudo. Run as your user."
  exit 2
fi

CPU="${COLIMA_CPU:-4}"
MEM="${COLIMA_MEM:-6}"
DISK="${COLIMA_DISK:-60}"   # desired minimum; existing VMs won't be shrunk

# Pick the right --arch for the host CPU
ARCH_FLAG="--arch aarch64"
if [[ "$(uname -m)" != "arm64" ]]; then
  ARCH_FLAG="--arch x86_64"
fi

PROFILE="$HOME/.colima/_lima/colima/colima.yaml"

# If a profile exists and requests a smaller disk than desired, bump it (prevents shrink attempts)
if [[ -f "$PROFILE" ]]; then
  CUR_CFG=$(/usr/bin/awk -F': *' '/^disk:/{print $2; exit}' "$PROFILE" 2>/dev/null || true)
  if [[ -n "${CUR_CFG:-}" && "$CUR_CFG" =~ ^[0-9]+$ ]] && (( CUR_CFG < DISK )); then
    /usr/bin/sed -i '' "s/^disk:\s*[0-9][0-9]*/disk: ${DISK}/" "$PROFILE" || true
  fi
fi

# Helper: parse current VM disk size (GiB) from status (portable AWK)
current_vm_disk_gib() {
  colima status 2>/dev/null | /usr/bin/awk -F': ' '/Disk/{print $2}' | /usr/bin/awk '{print $1}' || true
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
  colima start --cpu "$CPU" --memory "$MEM" --disk "$DISK" $ARCH_FLAG
fi

# Point Docker CLI to Colima, and ensure no stale override
docker context use colima
unset DOCKER_HOST

# Sanity
colima status || true
docker info | grep -E 'Context:|Server Version' || true
echo "✅ Colima ready (docker context = colima)."
