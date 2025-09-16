#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/infrastructure/compose_wrapper.sh"
cd "$(dirname "$0")/../services/immich"
compose ps
