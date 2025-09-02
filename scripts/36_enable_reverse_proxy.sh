#!/usr/bin/env bash
set -euo pipefail

# Ensure Caddy service is running
if ! pgrep -f "[c]addy run" >/dev/null 2>&1; then
  echo "Caddy does not appear to be running. Run ./scripts/35_install_caddy.sh first."
  exit 1
fi

# Point Tailscale HTTPS (443) to Caddy on localhost:8443
echo "Configuring Tailscale Serve to forward HTTPS:443 -> http://localhost:8443"
sudo tailscale serve --reset || true
sudo tailscale serve --https=443 http://localhost:8443

echo "Reverse proxy enabled. Browser URLs inside tailnet:"
echo "  https://<macmini>.<tailnet>.ts.net/photos"
echo "  https://<macmini>.<tailnet>.ts.net/plex"
