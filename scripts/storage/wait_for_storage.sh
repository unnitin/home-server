#!/usr/bin/env bash
# scripts/wait_for_storage.sh
# Wait for storage mounts and directory structure to be ready before starting services

set -euo pipefail

TIMEOUT=300  # 5 minutes max wait
echo "$(date): Waiting for storage prerequisites..."

# Function to wait for directory with timeout
wait_for_directory() {
    local dir_path="$1"
    local description="$2"
    local count=0
    
    while [[ ! -d "$dir_path" && $count -lt $TIMEOUT ]]; do
        echo "Waiting for $description... ($count/$TIMEOUT)"
        sleep 2
        ((count += 2))
    done
    
    if [[ ! -d "$dir_path" ]]; then
        echo "ERROR: $description not available after $TIMEOUT seconds"
        exit 1
    fi
    
    echo "✅ $description ready: $(ls -ld "$dir_path")"
}

# Wait for required storage mounts and directories
wait_for_directory "/Volumes/warmstore" "warmstore RAID"
wait_for_directory "/Volumes/faststore" "faststore RAID" 
wait_for_directory "/Volumes/faststore/immich" "Immich service directory"

echo "✅ All storage prerequisites ready for service startup"

exit 0
