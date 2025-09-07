#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Colima & Docker"
if command -v colima >/dev/null 2>&1; then ok "colima present"; else warn "colima missing"; fi
if command -v docker >/dev/null 2>&1; then ok "docker present: $(docker --version)"; else warn "docker missing (will be installed by scripts)"; fi
if docker info >/dev/null 2>&1; then ok "docker daemon reachable"; else warn "docker daemon not reachable (start Colima: scripts/21_start_colima.sh)"; fi
if docker compose version >/dev/null 2>&1; then ok "docker compose plugin present"; else warn "docker compose plugin missing"; fi

print_summary
