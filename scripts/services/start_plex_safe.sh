#!/usr/bin/env bash
# Start Plex Media Server if it isn't answering. Run by LaunchD (io.homelab.plex).
# Everything it needs (app, health URL, port, data tier) comes from the manifest;
# the steps are in lib/native_app.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/native_app.sh
source "$SCRIPT_DIR/lib/native_app.sh"

start_native_app plex
