#!/usr/bin/env bash
set -euo pipefail
host="${1:-localhost}"
ports=(32400 2283)
for p in "${ports[@]}"; do
  echo -n "Checking $host:$p ... "
  (echo >/dev/tcp/$host/$p) >/dev/null 2>&1 && echo "open" || echo "closed"
done
