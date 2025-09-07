#!/usr/bin/env bash
set -euo pipefail
# Compose command shim: supports both 'docker compose' and legacy 'docker-compose'
compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "❌ Neither 'docker compose' nor 'docker-compose' is installed."
    echo "   Install Docker Desktop or 'brew install docker-compose'."
    exit 1
  fi
}
