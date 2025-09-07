#!/usr/bin/env bash
set -euo pipefail
brew install caddy
BREW_PREFIX="$(brew --prefix)"
WEB_ROOT="${BREW_PREFIX}/var/www/hakuna_mateti"
mkdir -p "$WEB_ROOT"
cp -R "$(pwd)/services/caddy/site/." "$WEB_ROOT/" 2>/dev/null || true
echo "Caddy installed. Site root: $WEB_ROOT"
