#!/usr/bin/env bash
set -euo pipefail

# Report available updates. Report only: nothing is upgraded, pulled or restarted.
#
# Applying updates is disabled on purpose until Phase 5 adds version pinning, an
# Immich database backup step and approval (docs/mcp-refactor/07-roadmap.md).
# Immich releases can include breaking changes, so an unattended nightly
# upgrade (what --apply used to do) is how a photo library gets broken.
#
# Usage: check_updates.sh
#   IMMICH_SERVER (default http://localhost:2283)

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

if [[ "${1:-}" == "--apply" ]]; then
    log_error "--apply is disabled: updates need version pinning, a database backup and approval first (Phase 5)."
    log_error "Run without --apply to see what's available."
    exit 2
fi

# LaunchD's default PATH doesn't include Homebrew (append, so an existing PATH wins)
for dir in /opt/homebrew/bin /usr/local/bin; do
    case ":$PATH:" in *":$dir:"*) ;; *) PATH="$PATH:$dir" ;; esac
done
export PATH
IMMICH_SERVER="${IMMICH_SERVER:-http://localhost:2283}"

log_info "Update check (report only)"

# --- Homebrew: what's outdated, per the metadata already on disk (no `brew update`)
if command -v brew >/dev/null 2>&1; then
    outdated=$(brew outdated --verbose 2>/dev/null || true)
    if [[ -n "$outdated" ]]; then
        log_info "Homebrew: $(wc -l <<<"$outdated" | tr -d ' ') outdated:"
        head -25 <<<"$outdated" | sed 's/^/    /'
    else
        log_info "Homebrew: nothing outdated"
    fi
else
    log_warn "Homebrew not found"
fi

# --- Immich: running version vs. latest release
running=$(curl -s -m 5 "$IMMICH_SERVER/api/server/version" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    print("v{major}.{minor}.{patch}".format(**v))
except (ValueError, KeyError, TypeError):
    pass
' || true)
latest=$(curl -s -m 10 -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/immich-app/immich/releases/latest | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["tag_name"])
except (ValueError, KeyError, TypeError):
    pass
' || true)

if [[ -z "$running" ]]; then
    log_warn "Immich: running version unknown ($IMMICH_SERVER not answering)"
elif [[ -z "$latest" ]]; then
    log_warn "Immich: running $running; latest release unknown (GitHub not reachable)"
elif [[ "$running" == "$latest" ]]; then
    log_info "Immich: $running is the latest release"
else
    log_info "Immich: $running running, $latest available. Read the release notes before upgrading:"
    log_info "    https://github.com/immich-app/immich/releases/tag/$latest"
fi

log_info "Done. Nothing was changed."
