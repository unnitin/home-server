#!/usr/bin/env bash
set -euo pipefail
# Start Colima with reasonable defaults for a homeserver
colima start --cpu 4 --memory 8 --disk 100 --vm-type=vz --arch=aarch64 || colima start
docker context use default || true
docker info
