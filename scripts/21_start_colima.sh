#!/usr/bin/env bash
set -euo pipefail

# Start Colima with reasonable defaults on Apple Silicon
colima start --cpu 4 --memory 6 --disk 60 --arch aarch64 || colima start

# Point Docker CLI at Colima (this is the key change)
docker context use colima

# Sanity checks
colima status
docker info | grep -E 'Context:|Server Version' || true

echo "Colima started and docker context set to 'colima'."