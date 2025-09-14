#!/usr/bin/env bash
set -euo pipefail

# Find every .sh file in repo (starting at repo root) and make it executable
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
find "$REPO_ROOT" -type f -name "*.sh" -exec chmod +x {} \;

echo "✅ All shell scripts in the repository are now executable."
