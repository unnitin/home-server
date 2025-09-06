#!/usr/bin/env bash
set -euo pipefail
# Prevent sleep and enable Wake-on-LAN
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo pmset -a womp 1
echo "Power settings tuned for 24/7."
