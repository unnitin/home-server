#!/usr/bin/env bash
# Start Plex Media Server if it isn't answering. Run by LaunchD (io.homelab.plex) with
# --foreground: it then stays running while the app answers (D32), so the job
# isn't relaunched every two minutes.
# Everything it needs (app, health URL, port, data tier) comes from the manifest;
# the steps are in lib/native_app.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/native_app.sh
source "$SCRIPT_DIR/lib/native_app.sh"

start_native_app plex
if [[ "${1:-}" == "--foreground" ]]; then
    watch_native_app plex
fi
