#!/usr/bin/env bash
set -euo pipefail
BREW_PREFIX="$(brew --prefix)"
CADDY_ETC="${BREW_PREFIX}/etc/caddy"
mkdir -p "$CADDY_ETC"
cp "$(pwd)/services/caddy/Caddyfile" "$CADDY_ETC/Caddyfile"
# Restart Caddy as the invoking user (avoid root-owned plists)
brew services stop caddy || true
sudo brew services stop caddy || true
rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.caddy.plist" 2>/dev/null || true
mkdir -p "$HOME/Library/LaunchAgents" && chown -R "$USER" "$HOME/Library/LaunchAgents"
brew services start caddy

sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "Reverse proxy enabled on tailnet HTTPS :443 → Caddy (:8443). Config in $CADDY_ETC/Caddyfile"
