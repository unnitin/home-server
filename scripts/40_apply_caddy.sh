#!/usr/bin/env bash
set -euo pipefail
SRC="${1:-caddy/Caddyfile.ports}"
DEST="/opt/homebrew/etc/Caddyfile"
sudo mkdir -p /opt/homebrew/etc
sudo ln -sf "$(pwd)/$SRC" "$DEST"
caddy validate --config "$DEST"
caddy fmt --overwrite --config "$DEST"
brew services restart caddy
echo "Caddy reloaded with $SRC"
