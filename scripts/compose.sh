#!/usr/bin/env bash
set -euo pipefail

# Try docker compose plugin first
if docker compose version >/dev/null 2>&1; then
  exec docker compose "$@"
fi

# Fallback to legacy docker-compose
if command -v docker-compose >/dev/null 2>&1; then
  exec docker-compose "$@"
fi

# Try to install docker-compose if Homebrew exists
if command -v brew >/dev/null 2>&1; then
  echo "No Docker Compose found. Attempting: brew install docker-compose ..."
  brew install docker-compose
  if command -v docker-compose >/dev/null 2>&1; then
    exec docker-compose "$@"
  fi
fi

echo "ERROR: Neither 'docker compose' plugin nor 'docker-compose' found."
echo "Install Docker Desktop or run: brew install docker-compose"
exit 1
