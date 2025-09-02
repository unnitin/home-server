#!/usr/bin/env bash
set -euo pipefail
# Prevent system sleep and enable auto power on
sudo systemsetup -setcomputersleep Never || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo pmset -a tcpkeepalive 1 womp 1
echo "Power & network sleep tuned for always-on operation."
