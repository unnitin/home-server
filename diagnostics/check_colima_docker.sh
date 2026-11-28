#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Colima & Docker"

if command -v colima >/dev/null 2>&1; then
    ok "colima installed"
    if colima status >/dev/null 2>&1; then
        ok "colima VM running"
    else
        fail "colima VM not running (start: scripts/infrastructure/start_docker.sh)"
    fi
else
    fail "colima not installed (install: scripts/infrastructure/install_docker.sh)"
fi

if command -v docker >/dev/null 2>&1; then
    ok "docker CLI: $(docker --version)"
else
    fail "docker CLI not installed (install: scripts/infrastructure/install_docker.sh)"
fi

if docker info >/dev/null 2>&1; then
    ok "docker daemon reachable"
else
    fail "docker daemon not reachable (start Colima: scripts/infrastructure/start_docker.sh)"
fi

if docker compose version >/dev/null 2>&1; then
    ok "docker compose plugin: $(docker compose version --short 2>/dev/null || echo present)"
else
    fail "docker compose plugin missing (brew install docker-compose)"
fi

print_summary
