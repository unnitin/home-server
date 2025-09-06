#!/usr/bin/env bash
set -euo pipefail
# Copy Caddyfile to Homebrew location and start service
CADDY_ETC="/opt/homebrew/etc/caddy"
[[ -d "$CADDY_ETC" ]] || CADDY_ETC="/usr/local/etc/caddy"
mkdir -p "$CADDY_ETC"
cp "$(pwd)/services/caddy/Caddyfile" "$CADDY_ETC/Caddyfile"
brew services restart caddy

# Map Tailscale Serve to Caddy on :443 (replaces direct mappings if any)
sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "Reverse proxy enabled on tailnet HTTPS :443 → Caddy → / (landing), /photos, /plex"
