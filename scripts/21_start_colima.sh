#!/usr/bin/env bash
set -euo pipefail

# Defaults (can override with COLIMA_CPU/MEM/DISK env vars)
CPU="${COLIMA_CPU:-4}"
MEM="${COLIMA_MEM:-6}"
DISK="${COLIMA_DISK:-60}"

# If an instance already exists, start it without size flags (avoid shrink)
if colima status >/dev/null 2>&1; then
  echo "Colima instance already exists; starting without resizing..."
  colima start
else
  echo "Creating new Colima instance: cpu=${CPU} mem=${MEM}G disk=${DISK}G"
  colima start --cpu "$CPU" --memory "$MEM" --disk "$DISK" --arch aarch64
fi

# Point Docker CLI to Colima
docker context use colima

# Sanity
colima status || true
docker info | grep -E 'Context:|Server Version' || true

echo "Colima started and docker context set to 'colima'."
