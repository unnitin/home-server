#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Run scripts/01_install_homebrew.sh first."
  exit 1
fi

echo "Installing Caddy via Homebrew..."
brew install caddy

CFG_DIR="/opt/homebrew/etc/caddy"
sudo mkdir -p "$CFG_DIR"
sudo cp services/caddy/Caddyfile "$CFG_DIR/Caddyfile"
sudo mkdir -p "$CFG_DIR/site"
sudo cp -R services/caddy/site/* "$CFG_DIR/site/"

echo "Starting Caddy (brew services)..."
sudo brew services start caddy

echo "Caddy installed and started. Listening on localhost:8443"
