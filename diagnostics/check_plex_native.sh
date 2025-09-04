#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Plex (Native)"
if pgrep -f "Plex Media Server" >/dev/null 2>&1; then ok "Plex process running"; else warn "Plex process not running (open -ga 'Plex Media Server')"; fi
tcp_open localhost 32400 || true
http_probe "http://localhost:32400/web/index.html" || true

print_summary
