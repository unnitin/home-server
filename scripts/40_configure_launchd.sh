#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

render(){ local src="$1" dst="$2"; sed "s#__REPO__#${REPO_ROOT}#g" "$src" > "$dst"; }

mkdir -p "$HOME/Library/LaunchAgents"

render "$REPO_ROOT/launchd/io.homelab.colima.plist" "$HOME/Library/LaunchAgents/io.homelab.colima.plist"
render "$REPO_ROOT/launchd/io.homelab.compose.immich.plist" "$HOME/Library/LaunchAgents/io.homelab.compose.immich.plist"
render "$REPO_ROOT/launchd/io.homelab.updatecheck.plist" "$HOME/Library/LaunchAgents/io.homelab.updatecheck.plist"
render "$REPO_ROOT/launchd/io.homelab.tailscale.plist" "$HOME/Library/LaunchAgents/io.homelab.tailscale.plist"

for p in io.homelab.colima io.homelab.compose.immich io.homelab.updatecheck io.homelab.tailscale; do
  launchctl unload "$HOME/Library/LaunchAgents/$p.plist" 2>/dev/null || true
  launchctl load   "$HOME/Library/LaunchAgents/$p.plist"
done

echo "Launch agents installed & loaded."
