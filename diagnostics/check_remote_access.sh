#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Remote access = tailscale serve. Compares the live mappings with the declared
# list in config/tailscale_serve.txt and checks Funnel (public internet) is off.
# Replaces check_reverse_proxy.sh: Caddy is no longer part of the setup.
# Standalone: finds the Tailscale CLI itself instead of sourcing scripts/.

MAPPINGS_FILE="${TAILSCALE_SERVE_MAPPINGS:-$ROOT/config/tailscale_serve.txt}"

section "Remote access (tailscale serve)"

TS=""
for candidate in "${TAILSCALE_BIN:-}" "$(command -v tailscale 2>/dev/null || true)" \
    /Applications/Tailscale.app/Contents/MacOS/Tailscale /opt/homebrew/bin/tailscale; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then TS="$candidate"; break; fi
done
if [[ -z "$TS" ]]; then
    fail "Tailscale CLI not found"
    print_summary
    exit $?
fi
if [[ ! -f "$MAPPINGS_FILE" ]]; then
    fail "Mappings file missing: $MAPPINGS_FILE"
    print_summary
    exit $?
fi

if ! json=$("$TS" serve status --json 2>/dev/null); then
    fail "Could not read 'tailscale serve status'"
    print_summary
    exit $?
fi

parsed=$(python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for hostport, web in sorted((data.get("Web") or {}).items()):
    proxy = ((web.get("Handlers") or {}).get("/") or {}).get("Proxy", "")
    print("map", hostport.rsplit(":", 1)[-1], proxy)
if any((data.get("AllowFunnel") or {}).values()):
    print("funnel on")
' <<<"$json")

if grep -q '^funnel on' <<<"$parsed"; then
    fail "Funnel is ON: something is exposed to the public internet (tailscale funnel status)"
else
    ok "Funnel off: mappings are tailnet-only"
fi

declared=" "
while read -r port backend service _; do
    [[ -z "${port:-}" || "$port" == \#* ]] && continue
    declared+="$port "
    live=$(awk -v p="$port" '$1 == "map" && $2 == p {print $3}' <<<"$parsed")
    if curl -s -o /dev/null -m 2 "$backend"; then up=true; else up=false; fi

    if [[ "$live" == "$backend" ]]; then
        if $up; then
            ok "$service: tailnet :$port -> $backend"
        else
            warn "$service: mapped :$port -> $backend, but the backend is not answering"
        fi
    elif [[ -n "$live" ]]; then
        fail "$service: :$port points at $live, expected $backend (run scripts/infrastructure/apply_tailscale_serve.sh)"
    elif $up; then
        fail "$service: not published on the tailnet (run scripts/infrastructure/apply_tailscale_serve.sh)"
    else
        warn "$service: not published, and $backend isn't running yet"
    fi
done < "$MAPPINGS_FILE"

while read -r kind port backend; do
    [[ "${kind:-}" == "map" ]] || continue
    if [[ "$declared" != *" $port "* ]]; then
        warn "Undeclared mapping :$port -> $backend (not in config/tailscale_serve.txt)"
    fi
done <<<"$parsed"

print_summary
