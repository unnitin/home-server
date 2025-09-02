#!/usr/bin/env bash
set -euo pipefail
# Bring up immich via docker compose (Plex runs natively now)
( cd services/immich && docker compose up -d )
echo "Immich deployed. Plex runs natively; install via scripts/31_install_native_plex.sh"
