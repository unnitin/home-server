#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../services/immich"
if [[ ! -f .env ]]; then
  echo "Creating .env from example; set IMMICH_DB_PASSWORD before production use."
  cp -n .env.example .env
fi
docker compose pull
docker compose up -d
docker compose ps
