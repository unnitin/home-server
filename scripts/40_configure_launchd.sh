#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Render plists with repo path
render(){
  local src="$1" dst="$2"
  sed "s#__REPO__#${REPO_ROOT}#g" "$src" > "$dst"
}

mkdir -p "$HOME/Library/LaunchAgents"

render "$REPO_ROOT/launchd/io.homelab.colima.plist" "$HOME/Library/LaunchAgents/io.homelab.colima.plist"
render "$REPO_ROOT/launchd/io.homelab.compose.immich.plist" "$HOME/Library/LaunchAgents/io.homelab.compose.immich.plist"
render "$REPO_ROOT/launchd/io.homelab.updatecheck.plist" "$HOME/Library/LaunchAgents/io.homelab.updatecheck.plist"
render "$REPO_ROOT/launchd/io.homelab.tailscale.plist" "$HOME/Library/LaunchAgents/io.homelab.tailscale.plist"

launchctl unload "$HOME/Library/LaunchAgents/io.homelab.colima.plist" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/io.homelab.compose.immich.plist" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/io.homelab.updatecheck.plist" 2>/dev/null || true
launchctl unload "$HOME/Library/LaunchAgents/io.homelab.tailscale.plist" 2>/dev/null || true

launchctl load "$HOME/Library/LaunchAgents/io.homelab.colima.plist"
launchctl load "$HOME/Library/LaunchAgents/io.homelab.compose.immich.plist"
launchctl load "$HOME/Library/LaunchAgents/io.homelab.updatecheck.plist"
launchctl load "$HOME/Library/LaunchAgents/io.homelab.tailscale.plist"

echo "Launch agents installed & loaded."
