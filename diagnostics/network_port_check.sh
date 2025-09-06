#!/usr/bin/env bash
set -euo pipefail
HOST="${1:-localhost}"; PORT="${2:-2283}"
nc -vz "$HOST" "$PORT" || true
