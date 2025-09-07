#!/usr/bin/env bash
set -euo pipefail
if pgrep -fl "Plex Media Server" >/dev/null; then
  echo "Plex is running"; exit 0
else
  echo "Plex not running"; exit 1
fi
