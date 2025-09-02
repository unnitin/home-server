#!/usr/bin/env bash
set -euo pipefail
PLIST_DIR="/Library/LaunchDaemons"
SRC_DIR="$(pwd)/launchd"
sudo mkdir -p "$PLIST_DIR"

# Only load Colima + Immich compose; Plex is native and manages itself
for p in io.homelab.colima.plist io.homelab.compose.immich.plist io.homelab.updatecheck.plist io.homelab.tailscale.plist ; do
  sudo cp "$SRC_DIR/$p" "$PLIST_DIR/$p"
  sudo chown root:wheel "$PLIST_DIR/$p"
  sudo chmod 644 "$PLIST_DIR/$p"
  sudo launchctl unload "$PLIST_DIR/$p" 2>/dev/null || true
  sudo launchctl load -w "$PLIST_DIR/$p"
done

echo "LaunchDaemons installed and loaded (Colima + Immich). Plex is native."
