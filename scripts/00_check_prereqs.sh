#!/usr/bin/env bash
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This toolkit is for macOS. Detected: $(uname -s)"; exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "Note: not running as root (sudo). That's fine for bootstrap; individual scripts may prompt for sudo."
fi
echo "macOS check OK."
