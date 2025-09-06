#!/usr/bin/env bash
set -euo pipefail
pgrep -fl "Plex Media Server" && echo "Plex is running" || echo "Plex not running"
