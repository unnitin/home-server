#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../infrastructure/compose_wrapper.sh"

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

echo "Checking Homebrew..."
brew update
if (( APPLY )); then
  brew upgrade || true
  brew upgrade --cask || true
fi

echo "Refreshing Immich images..."
( cd "$(dirname "$0")/../services/immich" && compose pull && (( APPLY )) && compose up -d || true )

echo "Done."
