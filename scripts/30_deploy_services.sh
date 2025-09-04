#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/services/immich"

# Ensure .env exists
if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
  echo "Created .env from example. Set IMMICH_DB_PASSWORD before production use."
fi

# Use the wrapper so we auto-detect compose flavor
bash "$ROOT/scripts/compose.sh" up -d
bash "$ROOT/scripts/compose.sh" ps
