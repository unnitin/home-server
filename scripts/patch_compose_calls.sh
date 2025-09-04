#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Patching shell scripts to use scripts/compose.sh ..."

changed=0
while IFS= read -r -d "" file; do
  before="$(md5 -q "$file" 2>/dev/null || md5sum "$file" | awk "{print \$1}")"
  # Replace 'docker compose' and 'docker-compose' invocations
  perl -i -pe 's/\bdocker compose\b/bash scripts\/compose.sh/g; s/\bdocker-compose\b/bash scripts\/compose.sh/g' "$file"
  after="$(md5 -q "$file" 2>/dev/null || md5sum "$file" | awk "{print \$1}")"
  if [ "$before" != "$after" ]; then
    echo "  Patched: $file"
    changed=$((changed+1))
  fi
done < <(find . -type f -name "*.sh" -print0)

echo "Done. Files changed: $changed"
echo "Note: For Makefiles or other runners, manually replace 'docker compose' with 'bash scripts/compose.sh'."
