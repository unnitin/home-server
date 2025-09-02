#!/usr/bin/env bash
set -euo pipefail
echo "Listing external physical disks. Identify the 4 SSD and 4 NVMe device nodes (e.g., disk4 disk5 ...)."
echo
diskutil list external physical
echo
echo "Tip: Use 'diskutil info diskX | grep -E \"Protocol|Device / Media Name|Solid State\"' to learn more."
