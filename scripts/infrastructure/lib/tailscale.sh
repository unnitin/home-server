#!/usr/bin/env bash
# Tailscale CLI helpers. Source this file; it defines functions only.
# Infrastructure module: depends on nothing outside core tools.

# Print the path of the Tailscale CLI.
# The Mac app doesn't put `tailscale` on PATH: its CLI is the app binary itself.
# TAILSCALE_BIN overrides the search (tests use it).
tailscale_cli() {
    local candidate
    for candidate in "${TAILSCALE_BIN:-}" \
        "$(command -v tailscale 2>/dev/null || true)" \
        /Applications/Tailscale.app/Contents/MacOS/Tailscale \
        /opt/homebrew/bin/tailscale \
        /usr/local/bin/tailscale; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Run a tailscale command. If the plain call is refused, retry once with
# non-interactive sudo, which never prompts, so it is safe under LaunchD.
# TS_NO_SUDO=1 disables the retry.
ts() {
    local bin
    bin=$(tailscale_cli) || { echo "tailscale CLI not found" >&2; return 127; }
    if "$bin" "$@" 2>/dev/null; then
        return 0
    fi
    [[ "${TS_NO_SUDO:-0}" == "1" ]] && return 1
    sudo -n "$bin" "$@"
}

# Print the current serve mappings, one "<https port> <backend>" per line.
ts_serve_mappings() {
    local json
    json=$(ts serve status --json) || return 1
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(0)
for hostport, web in sorted((data.get("Web") or {}).items()):
    port = hostport.rsplit(":", 1)[-1]
    proxy = ((web.get("Handlers") or {}).get("/") or {}).get("Proxy", "")
    print(port, proxy)
' <<<"$json"
}

# Exit 0 if Funnel (public internet access) is enabled for any mapping.
ts_funnel_enabled() {
    local json
    json=$(ts serve status --json) || return 1
    python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
sys.exit(0 if any((data.get("AllowFunnel") or {}).values()) else 1)
' <<<"$json"
}

# Print this machine's MagicDNS name without the trailing dot (empty if unknown).
ts_hostname() {
    ts status --json 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))
except (ValueError, KeyError, TypeError):
    pass
' || true
}
