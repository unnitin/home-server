#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../scripts/_compose.sh"
cd "$(dirname "$0")/../services/immich"
compose ps
