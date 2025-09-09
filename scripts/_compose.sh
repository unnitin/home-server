#!/usr/bin/env bash
set -euo pipefail
# Compose command shim: supports both 'docker compose' and legacy 'docker-compose'
compose() {
  if command -v docker >/dev/null 2>&1 && scripts/compose_helper.sh services/immich version >/dev/null 2>&1; then
    scripts/compose_helper.sh services/immich "$@"
  elif command -v scripts/compose_helper.sh services/immich >/dev/null 2>&1; then
    scripts/compose_helper.sh services/immich "$@"
  else
    echo "❌ Neither 'docker compose' nor 'docker-compose' is installed."
    echo "   Install Docker Desktop or 'brew install docker-compose'."
    exit 1
  fi
}
