#!/usr/bin/env bash
set -euo pipefail
brew install --cask plex-media-server
open -ga "Plex Media Server" || true
echo "Plex installed. Visit http://localhost:32400/web"
