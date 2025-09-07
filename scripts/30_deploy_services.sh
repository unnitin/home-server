#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_compose.sh"
cd "$(dirname "$0")/../services/immich"

if [[ ! -f .env ]]; then
  echo "Creating .env from example; set IMMICH_DB_PASSWORD before production use."
  cp -n .env.example .env
fi

compose pull
compose up -d
compose ps
