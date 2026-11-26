#!/usr/bin/env bash
# Compose shim for Immich. Source it, then: compose ps | compose up -d | compose logs -f server
# Runs scripts/infrastructure/compose_wrapper.sh in the Immich folder named in the
# manifest (services.immich.compose_dir), from any working folder.
set -euo pipefail

# shellcheck source=../../core/environment.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../core/environment.sh"

compose() {
    if ! command -v docker >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
        echo "❌ Neither 'docker compose' nor 'docker-compose' is installed." >&2
        echo "   Install Docker (CLI) or 'brew install docker-compose'." >&2
        return 127
    fi
    "$HOMELAB_REPO/scripts/infrastructure/compose_wrapper.sh" \
        "$HOMELAB_REPO/$HOMELAB_SVC_IMMICH_COMPOSE_DIR" "$@"
}
