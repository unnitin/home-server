#!/usr/bin/env bash
# scripts/wait_for_storage.sh
# Wait for storage mounts to be ready before starting services

set -euo pipefail

TIMEOUT=300  # 5 minutes max wait
COUNT=0

echo "$(date): Waiting for storage prerequisites..."

# Wait for warmstore RAID to be available
while [[ ! -d "/Volumes/warmstore" && $COUNT -lt $TIMEOUT ]]; do
    echo "Waiting for warmstore RAID... ($COUNT/$TIMEOUT)"
    sleep 2
    ((COUNT += 2))
done

if [[ ! -d "/Volumes/warmstore" ]]; then
    echo "ERROR: warmstore RAID not available after $TIMEOUT seconds"
    exit 1
fi

# Wait for Photos symlink to be created
COUNT=0
while [[ ! -L "/Volumes/Photos" && $COUNT -lt $TIMEOUT ]]; do
    echo "Waiting for Photos mount symlink... ($COUNT/$TIMEOUT)"
    sleep 2
    ((COUNT += 2))
done

if [[ ! -L "/Volumes/Photos" ]]; then
    echo "ERROR: Photos symlink not available after $TIMEOUT seconds"
    exit 1
fi

# Verify the symlink actually works
if [[ ! -d "/Volumes/Photos" ]]; then
    echo "ERROR: Photos symlink exists but target directory is not accessible"
    exit 1
fi

echo "✅ Storage prerequisites ready:"
echo "  - warmstore RAID: $(ls -ld /Volumes/warmstore)"
echo "  - Photos mount: $(ls -ld /Volumes/Photos)"
echo "  - Target: $(readlink /Volumes/Photos)"

exit 0
