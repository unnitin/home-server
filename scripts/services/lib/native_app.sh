#!/usr/bin/env bash
# Start a native macOS app from the manifest (config/homelab.yaml), safely.
# Source it; don't run it:
#
#   source "$SCRIPT_DIR/lib/native_app.sh"
#   start_native_app plex
#
# 1. Already answering its health URL: nothing to do.
# 2. Its data tier (data_tier) must be mounted, by diskutil's account (D22).
# 3. A tailnet mapping on the app's port can stop it binding, so the mapping is
#    taken down while the app starts, and every mapping in the manifest is put
#    back afterwards (apply_tailscale_serve.sh), whether or not it started.
# 4. Waits up to START_TIMEOUT seconds (default 60) for the health URL.
# Returns 0 when the app answers, 1 otherwise.
#
#   watch_native_app plex     # after start_native_app, under LaunchD (D32)
#
# Stays in the foreground while the app answers, checking every WATCH_INTERVAL
# seconds (default 60), and returns 1 once it has failed WATCH_FAILS checks in a
# row (default 3). So the LaunchD job runs once per app start, and KeepAlive
# starts the app again only when it has really stopped answering.
#
#   quit_native_app plex      # for a restart (restart_native_app.sh)
#
# Asks every process of the app's bundle to quit (TERM), waits up to
# QUIT_TIMEOUT seconds (default 30), then kills what's left.

set -euo pipefail

_NATIVE_APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../core/environment.sh
source "$_NATIVE_APP_DIR/../../core/environment.sh"
# shellcheck source=../../infrastructure/lib/tailscale.sh
source "$_NATIVE_APP_DIR/../../infrastructure/lib/tailscale.sh"

HOMELAB_APPS_DIR="${HOMELAB_APPS_DIR:-/Applications}"   # tests point this elsewhere

_svc() { local v; v="HOMELAB_SVC_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_$2"; printf '%s' "${!v:-}"; }

_healthy() {  # _healthy URL EXPECTED_CODE
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$1" 2>/dev/null || true)
    [[ "$code" == "$2" ]]
}

start_native_app() {
    local svc="$1" app url expect port tier mount timeout interval waited serve_off=false
    app=$(_svc "$svc" APP)
    url=$(_svc "$svc" HEALTH_URL)
    expect=$(_svc "$svc" HEALTH_EXPECT)
    port=$(_svc "$svc" PORTS); port="${port%% *}"
    tier=$(_svc "$svc" DATA_TIER)
    timeout="${START_TIMEOUT:-60}"
    interval="${START_INTERVAL:-2}"
    ((interval >= 1)) || interval=1   # 0 would never reach the timeout
    if [[ -z "$app" || -z "$url" ]]; then
        echo "❌ $svc is not a native app with a health URL in the manifest" >&2
        return 1
    fi

    echo "$(date): Starting $app safely..."
    if _healthy "$url" "$expect"; then
        echo "$app already running and answering ($url)"
        return 0
    fi

    if [[ -n "$tier" ]]; then
        mount=$(homelab_tier_mount "$tier")
        if ! homelab_is_mounted "$mount"; then
            echo "❌ $tier is not mounted at $mount: $app's data lives there. Not starting it." >&2
            return 1
        fi
    fi
    if [[ ! -d "$HOMELAB_APPS_DIR/$app.app" ]]; then
        echo "❌ $app.app not found in $HOMELAB_APPS_DIR" >&2
        return 1
    fi

    if [[ -n "$port" ]] && ts_serve_mappings 2>/dev/null | awk -v p="$port" '$1 == p { found = 1 } END { exit !found }'; then
        echo "Taking down the tailnet mapping on :$port while $app starts..."
        ts serve --https="$port" off >/dev/null 2>&1 || true
        serve_off=true
    fi

    open -a "$app"
    waited=0
    until _healthy "$url" "$expect"; do
        if ((waited >= timeout)); then
            break
        fi
        echo "Waiting for $app... (${waited}/${timeout}s)"
        sleep "$interval"
        waited=$((waited + interval))   # a post-increment in (( )) returns 1 at 0, which ends a set -e script (D30)
    done

    if $serve_off; then
        echo "Restoring the tailnet mappings from the manifest..."
        "$HOMELAB_REPO/scripts/infrastructure/apply_tailscale_serve.sh" --wait 30 ||
            echo "⚠️  Some mappings were not restored: run scripts/infrastructure/apply_tailscale_serve.sh"
    fi

    if _healthy "$url" "$expect"; then
        echo "✅ $app started and answering ($url)"
        return 0
    fi
    echo "❌ $app did not answer $url within ${timeout}s" >&2
    return 1
}

watch_native_app() {
    local svc="$1" url expect interval limit fails=0
    url=$(_svc "$svc" HEALTH_URL)
    expect=$(_svc "$svc" HEALTH_EXPECT)
    interval="${WATCH_INTERVAL:-60}"
    limit="${WATCH_FAILS:-3}"
    ((interval >= 1)) || interval=1
    echo "$(date): Watching $svc ($url every ${interval}s)"
    while true; do
        sleep "$interval"
        if _healthy "$url" "$expect"; then
            fails=0
            continue
        fi
        fails=$((fails + 1))
        echo "$(date): $svc not answering ($fails/$limit)"
        if ((fails >= limit)); then
            echo "$(date): $svc stopped answering; exiting so LaunchD starts it again" >&2
            return 1
        fi
    done
}

_app_pids() {  # the PIDs of every process running from the app's bundle
    pgrep -f "$HOMELAB_APPS_DIR/$1.app/Contents/" 2>/dev/null || true
}

quit_native_app() {
    local svc="$1" app pids waited=0 timeout
    app=$(_svc "$svc" APP)
    timeout="${QUIT_TIMEOUT:-30}"
    [[ -n "$app" ]] || { echo "❌ $svc is not a native app in the manifest" >&2; return 1; }
    pids=$(_app_pids "$app")
    if [[ -z "$pids" ]]; then
        echo "$app is not running"
        return 0
    fi
    echo "$(date): Asking $app to quit (PIDs: $(tr '\n' ' ' <<<"$pids"))"
    # shellcheck disable=SC2086  # one PID per word
    kill -TERM $pids 2>/dev/null || true
    while [[ -n "$(_app_pids "$app")" ]] && ((waited < timeout)); do
        sleep 1
        waited=$((waited + 1))
    done
    pids=$(_app_pids "$app")
    if [[ -n "$pids" ]]; then
        echo "⚠️  $app still running after ${timeout}s; killing it"
        # shellcheck disable=SC2086
        kill -KILL $pids 2>/dev/null || true
        sleep 1
    fi
    echo "$(date): $app has quit"
}
