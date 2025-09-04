#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

section "Immich (Docker)"
if [ -f "$ROOT/services/immich/docker-compose.yml" ]; then
  ok "Found docker-compose.yml"
else
  fail "services/immich/docker-compose.yml missing"
fi

tcp_open localhost 2283 || true
http_probe "http://localhost:2283" || true

print_summary
