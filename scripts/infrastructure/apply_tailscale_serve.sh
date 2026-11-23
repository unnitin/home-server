#!/usr/bin/env bash
set -euo pipefail

# Apply the tailnet HTTPS mappings in config/tailscale_serve.txt with `tailscale serve`.
#   - Adds a missing mapping once its backend answers (waits up to --wait seconds).
#   - Repoints a port that is mapped to the wrong backend.
#   - Never resets, and leaves mappings that aren't in the file alone (it reports them).
#   - Serve only, never Funnel: mappings are reachable from tailnet devices only.
#
# Usage: apply_tailscale_serve.sh [--dry-run] [--wait SECONDS]
#   TEST_MODE=1 implies --dry-run. TAILSCALE_SERVE_MAPPINGS overrides the file.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=lib/tailscale.sh
source "$SCRIPT_DIR/lib/tailscale.sh"

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

MAPPINGS_FILE="${TAILSCALE_SERVE_MAPPINGS:-$REPO_ROOT/config/tailscale_serve.txt}"
DRY_RUN=false
WAIT=60

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --wait) WAIT="${2:?--wait needs a number of seconds}"; shift ;;
        -h|--help) sed -n '4,11p' "$0"; exit 0 ;;
        *) log_error "Unknown option: $1"; exit 2 ;;
    esac
    shift
done
if [[ "${TEST_MODE:-0}" == "1" ]]; then
    DRY_RUN=true
fi

if ! tailscale_cli >/dev/null; then
    log_error "Tailscale CLI not found (install the Tailscale app, or: brew install tailscale)"
    exit 1
fi
if [[ ! -f "$MAPPINGS_FILE" ]]; then
    log_error "Mappings file not found: $MAPPINGS_FILE"
    exit 1
fi
if ! current=$(ts_serve_mappings); then
    log_error "Could not read 'tailscale serve status'"
    exit 1
fi

# Any HTTP response counts as "up" (some backends answer 401/404/405 at the root).
backend_up() { curl -s -o /dev/null -m 2 "$1"; }

$DRY_RUN && log_info "Dry run: nothing will be changed"
deadline=$((SECONDS + WAIT))
changed=0
skipped=0
failed=0
declared=" "

while read -r port backend service _; do
    [[ -z "${port:-}" || "$port" == \#* ]] && continue
    declared+="$port "
    live=$(awk -v p="$port" '$1 == p {print $2}' <<<"$current")

    if [[ "$live" == "$backend" ]]; then
        log_info "$service: :$port -> $backend (already mapped)"
        continue
    fi
    if [[ -n "$live" ]]; then
        action="repoint :$port from $live to $backend"
    else
        action="map :$port -> $backend"
    fi

    if $DRY_RUN; then
        if backend_up "$backend"; then state="backend up"; else state="backend down: would wait up to ${WAIT}s"; fi
        log_info "$service: would $action ($state)"
        changed=$((changed + 1))
        continue
    fi

    until backend_up "$backend" || (( SECONDS >= deadline )); do
        sleep 2
    done
    if ! backend_up "$backend"; then
        log_warn "$service: backend $backend not answering, skipped (re-run once it is up)"
        skipped=$((skipped + 1))
        continue
    fi

    if ts serve --bg --https="$port" "$backend" >/dev/null; then
        log_info "$service: $action"
        changed=$((changed + 1))
    else
        log_error "$service: failed to $action"
        failed=$((failed + 1))
    fi
done < "$MAPPINGS_FILE"

# Report, never remove, mappings that aren't declared in the file
while read -r port backend; do
    [[ -z "${port:-}" ]] && continue
    if [[ "$declared" != *" $port "* ]]; then
        log_warn "Undeclared mapping left in place: :$port -> $backend"
    fi
done <<<"$current"

if ts_funnel_enabled; then
    log_warn "Funnel is enabled: something is exposed to the public internet. Check 'tailscale funnel status'"
fi

if $DRY_RUN; then
    log_info "Done: $changed would change, $failed failed"
else
    log_info "Done: $changed changed, $skipped skipped, $failed failed"
fi
exit $((failed > 0 ? 1 : 0))
