#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Run scripts/01_install_homebrew.sh first."
  exit 1
fi

echo "Installing Tailscale via Homebrew..."
brew install tailscale

echo "Enabling Tailscale service (tailscaled)..."
sudo brew services start tailscale

echo "Run the following once to authenticate this Mac mini:"
echo "  sudo tailscale up --accept-dns=true"

echo "After login, enable HTTPS proxy for Immich:"
echo "  sudo tailscale serve --https=443 http://localhost:2283   # Immich
sudo tailscale serve --https=32400 http://localhost:32400 # Plex"
echo
echo "Immich will then be reachable at:"
echo "  https://<macmini-name>.<tailnet>.ts.net"


echo "Optionally proxy Plex over HTTPS as well:"
echo "  sudo tailscale serve --https=32400 http://localhost:32400"
echo
echo "Then Plex is reachable at:"
echo "  https://<macmini-name>.<tailnet>.ts.net:32400"
