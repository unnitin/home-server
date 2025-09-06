#!/usr/bin/env bash
set -euo pipefail
echo "Listing disks (external often are candidates):"
diskutil list
echo
echo "Hint: to get internal/external info:"
system_profiler SPNVMeDataType SPSerialATADataType | sed -n '1,200p' || true
