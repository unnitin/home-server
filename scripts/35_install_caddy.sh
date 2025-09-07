#!/usr/bin/env bash
set -euo pipefail
brew install caddy
# Stage site
mkdir -p /usr/local/var/www/hakuna_mateti || true
cp -R "$(pwd)/services/caddy/site/." /usr/local/var/www/hakuna_mateti/ 2>/dev/null || true
echo "Caddy installed."
