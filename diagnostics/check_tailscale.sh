#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Tailscale"

# The Mac app's CLI isn't on PATH, so look inside the app bundle too.
TS=""
for candidate in "${TAILSCALE_BIN:-}" "$(command -v tailscale 2>/dev/null || true)" \
    /Applications/Tailscale.app/Contents/MacOS/Tailscale /opt/homebrew/bin/tailscale; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then TS="$candidate"; break; fi
done

if [[ -z "$TS" ]]; then
    fail "Tailscale CLI not found (install the Tailscale app, or: brew install tailscale)"
    print_summary
    exit $?
fi
ok "Tailscale CLI: $TS ($("$TS" version 2>/dev/null | head -1 || echo "version unknown"))"

if "$TS" status >/dev/null 2>&1; then
    ok "Connected to the tailnet"
else
    fail "Not connected to the tailnet (open the Tailscale app, or: tailscale up)"
fi

ip=$("$TS" ip -4 2>/dev/null | head -1 || true)
if [[ -n "$ip" ]]; then
    ok "Tailnet IP: $ip"
fi

info "Published services: see check_remote_access.sh"

print_summary
