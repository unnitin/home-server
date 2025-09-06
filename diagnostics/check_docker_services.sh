#!/usr/bin/env bash
set -euo pipefail
docker compose -f "$(dirname "$0")/../services/immich/docker-compose.yml" ps
