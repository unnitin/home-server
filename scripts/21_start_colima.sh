#!/usr/bin/env bash
set -euo pipefail
colima start --cpu 4 --memory 6 --disk 60 --arch aarch64 || colima start
docker context use default || true
echo "Colima started."
