#!/usr/bin/env bash
set -euo pipefail

# Ensure we're in repo root no matter where called from
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=../core/environment.sh
source "$ROOT/scripts/core/environment.sh"
IMMICH_DIR="$ROOT/$HOMELAB_SVC_IMMICH_COMPOSE_DIR"   # from the manifest

# Make sure compose helper exists
if [[ ! -x "$ROOT/scripts/infrastructure/compose_wrapper.sh" ]]; then
  echo "❌ scripts/infrastructure/compose_wrapper.sh not found or not executable."
  exit 1
fi

# Ensure service .env and remind about DB password
if [[ ! -f "$IMMICH_DIR/.env" ]]; then
  ( cd "$IMMICH_DIR" && cp -n .env.example .env )
  echo ">> Set IMMICH_DB_PASSWORD in $HOMELAB_SVC_IMMICH_COMPOSE_DIR/.env before production use."
fi

# Ensure docker context is colima (daemon needs to be up first)
docker context use colima >/dev/null 2>&1 || true

# Pull & start Immich via the unified wrapper
"$ROOT/scripts/infrastructure/compose_wrapper.sh" "$IMMICH_DIR" pull
"$ROOT/scripts/infrastructure/compose_wrapper.sh" "$IMMICH_DIR" up -d
"$ROOT/scripts/infrastructure/compose_wrapper.sh" "$IMMICH_DIR" ps
