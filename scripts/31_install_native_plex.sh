#!/usr/bin/env bash
set -euo pipefail
# Install Plex Media Server natively (macOS app) for proper hardware transcoding.
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew not found. Run scripts/01_install_homebrew.sh first."
  exit 1
fi

brew install --cask plex-media-server

cat <<'EOS'
Plex Media Server installed.

Next steps:
1) Open Plex Web: http://localhost:32400/web
2) Sign in and go to Settings → Transcoder → enable "Use hardware acceleration when available" (Plex Pass required).
3) Create libraries pointing to:
   - Movies: /Volumes/Media/Movies
   - TV:     /Volumes/Media/TV
   - Music:  /Volumes/Media/Music

Plex installs a LaunchAgent that auto-starts the server at login/boot.
EOS
