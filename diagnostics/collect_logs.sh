#!/usr/bin/env bash
set -euo pipefail
tar -czf /tmp/homeserver-logs.tgz /tmp/*.out /tmp/*.err 2>/dev/null || true
echo "/tmp/homeserver-logs.tgz"
