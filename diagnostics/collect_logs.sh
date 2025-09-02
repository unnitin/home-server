#!/usr/bin/env bash
set -euo pipefail
OUT="homeserver-logs-$(date +%Y%m%d%H%M%S).tar.gz"
tmp=$(mktemp -d)
mkdir -p "$tmp"/{launchd,docker,services}
cp /var/log/colima.* "$tmp/launchd" 2>/dev/null || true
cp /var/log/compose-*.log "$tmp/launchd" 2>/dev/null || true
docker ps > "$tmp/docker/ps.txt" 2>/dev/null || true
docker logs plex > "$tmp/docker/plex.log" 2>/dev/null || true
docker logs immich-server > "$tmp/docker/immich-server.log" 2>/dev/null || true
tar -C "$tmp" -czf "$OUT" .
rm -rf "$tmp"
echo "Wrote $OUT"
