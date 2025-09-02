#!/usr/bin/env bash
set -euo pipefail
# Enable SSH
sudo systemsetup -setremotelogin on || true

# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
echo "SSH enabled and firewall turned on."
