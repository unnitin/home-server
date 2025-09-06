#!/usr/bin/env bash
set -euo pipefail
# Enable Remote Login (SSH)
sudo systemsetup -setremotelogin on

# Enable and configure Application Firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
# Allow Caddy, Docker, Plex when present
for app in "/Applications/Plex Media Server.app" "/opt/homebrew/bin/caddy" "/opt/homebrew/bin/docker"; do
  [[ -e "$app" ]] && sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "$app" || true
done

echo "SSH & firewall configured. Consider limiting SSH to your Tailnet IPs."
