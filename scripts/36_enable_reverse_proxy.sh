#!/usr/bin/env bash
set -euo pipefail
CADDY_ETC="/opt/homebrew/etc/caddy"
[[ -d "$CADDY_ETC" ]] || CADDY_ETC="/usr/local/etc/caddy"
mkdir -p "$CADDY_ETC"
cp "$(pwd)/services/caddy/Caddyfile" "$CADDY_ETC/Caddyfile"
brew services restart caddy

# Tailscale HTTPS -> Caddy
sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "Reverse proxy enabled via Caddy on tailnet :443"
