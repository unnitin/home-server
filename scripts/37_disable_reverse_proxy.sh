#!/usr/bin/env bash
set -euo pipefail
echo "Disabling reverse proxy routing on Tailscale Serve..."
sudo tailscale serve --reset || true
echo "Leaving Caddy running (safe). To stop:"
echo "  sudo brew services stop caddy"
