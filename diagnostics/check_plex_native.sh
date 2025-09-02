#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${HOME}/Library/Logs/Plex Media Server"
echo "== Plex Native Status =="
if pgrep -f "Plex Media Server" >/dev/null 2>&1; then
  echo "Plex is running."
else
  echo "Plex is NOT running."
fi

echo
echo "== Recent Plex Logs =="
if [[ -d "$LOG_DIR" ]]; then
  ls -lt "$LOG_DIR" | head -n 10
  echo
  log_file="$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -n1 || true)"
  if [[ -n "${log_file:-}" ]]; then
    echo "Tail of: $log_file"
    tail -n 50 "$log_file" || true
  else
    echo "No log files found in $LOG_DIR"
  fi
else
  echo "Log directory not found: $LOG_DIR"
fi
