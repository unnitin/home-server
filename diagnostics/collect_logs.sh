#!/usr/bin/env bash
set -euo pipefail
OUT="/tmp/homeserver-logs-$(date +%Y%m%d-%H%M%S).tgz"
tar -czf "$OUT" /tmp/*.out /tmp/*.err 2>/dev/null || true
echo "$OUT"
