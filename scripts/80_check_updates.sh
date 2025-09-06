#!/usr/bin/env bash
set -euo pipefail
APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

echo "Checking Homebrew..."
brew update
if (( APPLY )); then
  brew upgrade || true
  brew upgrade --cask || true
fi

echo "Refreshing Immich images..."
( cd "$(dirname "$0")/../services/immich" && docker compose pull && (( APPLY )) && docker compose up -d || true )

echo "Done."
