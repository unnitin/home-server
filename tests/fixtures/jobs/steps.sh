#!/usr/bin/env bash
# A test job: prints progress, records when it ran, sleeps, exits with $1.
#   steps.sh EXIT_CODE SECONDS MARKER_FILE
set -euo pipefail
code="${1:-0}" secs="${2:-0}" marker="${3:-/dev/null}"
echo "start $(date +%s.%N 2>/dev/null || date +%s)" >>"$marker"
echo "::stage working"
echo "::progress 50"
sleep "$secs"
echo "::result {\"items\": 3}"
echo "end $(date +%s)" >>"$marker"
exit "$code"
