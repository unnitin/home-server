#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Run scripts/01_install_homebrew.sh first."
  exit 1
fi

echo "Installing Caddy reverse proxy..."
brew install caddy

echo "Placing Caddyfile..."
sudo mkdir -p /usr/local/etc
sudo cp services/caddy/Caddyfile /usr/local/etc/Caddyfile

echo "Starting Caddy as a service..."
sudo brew services start caddy

echo "Routing Tailscale HTTPS (443) to Caddy (localhost:8443)..."
sudo tailscale serve --https=443 http://localhost:8443

cat <<EOF

Caddy reverse proxy is running.

Web access inside your tailnet:
  Immich → https://<macmini>.<tailnet>.ts.net/photos
  Plex   → https://<macmini>.<tailnet>.ts.net/plex
  Landing page → https://<macmini>.<tailnet>.ts.net/

Note: For mobile apps, still use:
  - Immich app → https://<macmini>.<tailnet>.ts.net
  - Plex app   → https://<macmini>.<tailnet>.ts.net:32400
EOF
