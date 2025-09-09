#!/usr/bin/env bash
set -euo pipefail

# Ensure we’re in repo root no matter where called from
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Make sure compose helper exists
if [[ ! -x "$ROOT/scripts/compose_helper.sh" ]]; then
  echo "❌ scripts/compose_helper.sh not found or not executable."
  exit 1
fi

# Ensure service .env and remind about DB password
if [[ ! -f "$ROOT/services/immich/.env" ]]; then
  ( cd "$ROOT/services/immich" && cp -n .env.example .env )
  echo ">> Set IMMICH_DB_PASSWORD in services/immich/.env before production use."
fi

# Ensure docker context is colima (daemon needs to be up first)
docker context use colima >/dev/null 2>&1 || true

# Pull & start Immich via the unified wrapper
"$ROOT/scripts/compose_helper.sh" "$ROOT/services/immich" pull
"$ROOT/scripts/compose_helper.sh" "$ROOT/services/immich" up -d
"$ROOT/scripts/compose_helper.sh" "$ROOT/services/immich" ps
