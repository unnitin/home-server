#!/usr/bin/env bash
set -euo pipefail

BREW_PREFIX="$(brew --prefix)"
CADDY_ETC="${BREW_PREFIX}/etc/caddy"
mkdir -p "$CADDY_ETC"
cp "$(pwd)/services/caddy/Caddyfile" "$CADDY_ETC/Caddyfile"

# Always manage Caddy as a USER service — never sudo here
brew services stop caddy || true
sudo brew services stop caddy || true
launchctl bootout gui/$(id -u)/homebrew.mxcl.caddy 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.caddy.plist" 2>/dev/null || true
brew services start caddy

# Tailscale mapping needs sudo (network capability)
sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "✅ Caddy running as user. HTTPS on Tailnet :443 → http://localhost:8443 (Caddy)."
echo "   Config: $CADDY_ETC/Caddyfile | Web root: $(brew --prefix)/var/www/hakuna_mateti"
