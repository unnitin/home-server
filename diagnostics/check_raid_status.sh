#!/usr/bin/env bash
set -euo pipefail
echo "== AppleRAID sets =="
diskutil appleRAID list || true
echo
echo "== Disk summary =="
diskutil list external physical || true
