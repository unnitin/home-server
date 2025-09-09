#!/usr/bin/env bash
set -euo pipefail
brew install tailscale
sudo brew services start tailscale || true
echo "Tailscale installed. Next: sudo tailscale up --accept-dns=true"
