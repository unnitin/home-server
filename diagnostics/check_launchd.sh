#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Checks every job defined in launchd/ (so new jobs are covered automatically)
# and reports each one's last exit status, not just whether it is loaded.

section "LaunchD jobs (current user)"

listing=$(launchctl list 2>/dev/null || true)

for plist in "$ROOT"/launchd/io.homelab.*.plist; do
    [[ -f "$plist" ]] || continue
    label=$(plutil -extract Label raw "$plist" 2>/dev/null || basename "$plist" .plist)
    row=$(awk -v l="$label" '$3 == l {print $1, $2}' <<<"$listing")

    if [[ -z "$row" ]]; then
        warn "Not loaded: $label"
        continue
    fi

    pid="${row%% *}"
    status="${row##* }"
    case "$status" in
        0)
            if [[ "$pid" == "-" ]]; then ok "$label: idle, last exit 0"; else ok "$label: running (pid $pid)"; fi
            ;;
        126)
            fail "$label: last exit 126, macOS blocked the script (repo under ~/Documents? see D19 in docs/mcp-refactor/01-assessment.md)"
            ;;
        127)
            fail "$label: last exit 127, command not found (check the plist paths and placeholders)"
            ;;
        *)
            if [[ "$pid" == "-" ]]; then
                fail "$label: last exit $status"
            else
                warn "$label: running (pid $pid), previous run exited $status"
            fi
            ;;
    esac
done

print_summary
