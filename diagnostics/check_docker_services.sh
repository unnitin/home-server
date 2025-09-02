#!/usr/bin/env bash
set -euo pipefail
echo "== Docker ps =="
docker ps
echo
echo "== Plex logs (last 50) =="
echo 'Plex is native; see diagnostics/check_plex_native.sh'
echo
echo "== Immich server logs (last 50) =="
docker logs --tail=50 immich-server || true
