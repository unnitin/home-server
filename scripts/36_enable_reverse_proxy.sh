#!/usr/bin/env bash
set -euo pipefail
BREW_PREFIX="$(brew --prefix)"
CADDY_ETC="${BREW_PREFIX}/etc/caddy"
mkdir -p "$CADDY_ETC"
cp "$(pwd)/services/caddy/Caddyfile" "$CADDY_ETC/Caddyfile"
brew services restart caddy

sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "Reverse proxy enabled on tailnet HTTPS :443 → Caddy (:8443). Config in $CADDY_ETC/Caddyfile"
