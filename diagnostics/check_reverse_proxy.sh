#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Caddy reverse proxy"
if command -v caddy >/dev/null 2>&1; then ok "caddy present"; else warn "caddy not installed"; fi

tcp_open localhost 8443 || true
http_probe "http://localhost:8443" || true
http_probe "http://localhost:8443/photos" || true
http_probe "http://localhost:8443/plex" || true

print_summary
