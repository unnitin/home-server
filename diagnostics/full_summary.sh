#!/usr/bin/env bash
set -euo pipefail

echo "=== Hakuna Mateti HomeServer Diagnostics ==="
date

echo -e "\n--- RAID status ---"
if command -v diskutil >/dev/null 2>&1; then
  diskutil appleRAID list || true
else
  echo "diskutil not available (this check is macOS-only)."
fi

echo -e "\n--- Storage mountpoints ---"
for d in /Volumes/Media /Volumes/Photos /Volumes/Archive; do
  echo "Checking $d"
  df -h "$d" 2>/dev/null || echo "❌ Not mounted"
done

echo -e "\n--- Plex status ---"
if pgrep -fl "Plex Media Server" >/dev/null 2>&1; then
  pgrep -fl "Plex Media Server"
else
  echo "❌ Plex not running"
fi

echo -e "\n--- Immich containers ---"
if command -v docker >/dev/null 2>&1; then
  cd "$(dirname "$0")/../services/immich"
  if scripts/compose_helper.sh services/immich version >/dev/null 2>&1; then
    scripts/compose_helper.sh services/immich ps || true
  elif command -v scripts/compose_helper.sh services/immich >/dev/null 2>&1; then
    scripts/compose_helper.sh services/immich ps || true
  else
    echo "❌ Neither 'docker compose' nor 'docker-compose' found"
  fi
  cd - >/dev/null || true
else
  echo "❌ Docker not installed or not in PATH"
fi

echo -e "\n--- Docker info ---"
docker context ls 2>/dev/null || true
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

echo -e "\n--- Network checks ---"
for port in 32400 2283 8443; do
  echo -n "Port $port: "
  nc -z localhost $port >/dev/null 2>&1 && echo "✅ Open" || echo "❌ Closed"
done

echo -e "\n--- Tailscale status ---"
if command -v tailscale >/dev/null 2>&1; then
  tailscale status || echo "❌ Tailscale not running"
else
  echo "tailscale not installed"
fi

echo -e "\n--- Recent logs (/tmp) ---"
ls -lh /tmp/*.out /tmp/*.err 2>/dev/null || echo "No logs found"

echo -e "\n✅ Diagnostics complete."
