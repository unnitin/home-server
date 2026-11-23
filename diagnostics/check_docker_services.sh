#!/usr/bin/env bash
set -euo pipefail

# Immich container health via Docker Compose.
# Standalone on purpose: uses the docker CLI directly and never sources scripts/,
# so it still works when the scripts tree is broken.

DIAG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIAG_DIR/diag_lib.sh"
ROOT="$(cd "$DIAG_DIR/.." && pwd)"

COMPOSE_DIR="$ROOT/services/immich"
PROJECT="${IMMICH_COMPOSE_PROJECT:-immich}"
EXPECTED=(immich-server immich-ml immich-redis immich-db)

section "Immich containers (compose project: $PROJECT)"

if ! command -v docker >/dev/null 2>&1; then
    fail "docker CLI not installed (install: scripts/infrastructure/install_docker.sh)"
    print_summary
    exit $?
fi
if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon not reachable (start Colima: scripts/infrastructure/start_docker.sh)"
    print_summary
    exit $?
fi

if ! ps_out=$(cd "$COMPOSE_DIR" && docker compose -p "$PROJECT" ps --all \
        --format '{{.Name}}\t{{.State}}\t{{.Health}}' 2>&1); then
    fail "docker compose ps failed: $ps_out"
    print_summary
    exit $?
fi

for name in "${EXPECTED[@]}"; do
    line=$(awk -F'\t' -v n="$name" '$1 == n' <<<"$ps_out")
    if [[ -z "$line" ]]; then
        fail "$name: container not found"
        continue
    fi
    state=$(cut -f2 <<<"$line")
    health=$(cut -f3 <<<"$line")
    if [[ "$state" != "running" ]]; then
        fail "$name: $state"
    elif [[ "$health" == "unhealthy" ]]; then
        fail "$name: running but unhealthy"
    elif [[ "$health" == "starting" ]]; then
        warn "$name: running, health check still starting"
    else
        ok "$name: running${health:+ ($health)}"
    fi
done

print_summary
