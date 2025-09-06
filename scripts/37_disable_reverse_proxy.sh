#!/usr/bin/env bash
set -euo pipefail
brew services stop caddy || true
# Remove tailscale serve mappings
sudo tailscale serve --reset || true
echo "Reverse proxy disabled. You can remap direct ports if desired."
