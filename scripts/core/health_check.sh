#!/usr/bin/env bash
set -euo pipefail

# Post-boot health check with guided recovery. Every job, tier, port and URL
# comes from the manifest (config/homelab.yaml) through environment.sh.
#
#   ./scripts/core/health_check.sh                 assess and print the fixes
#   ./scripts/core/health_check.sh --auto-recover  also start Colima and Plex,
#                                                  and restart the landing job
#
# Storage is never repaired automatically: nothing is created where a volume
# should be (D22, D25).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=environment.sh
source "${SCRIPT_DIR}/environment.sh"

AUTO_RECOVER=false
if [[ "${1:-}" == "--auto-recover" ]]; then
    AUTO_RECOVER=true
    shift
fi

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }
svc_var() { local v; v="HOMELAB_SVC_$(upper "$1")_$2"; printf '%s' "${!v:-}"; }

echo "🏥 System Health Check & Recovery"
echo "================================"
if $AUTO_RECOVER; then
    echo "🚀 Auto-recovery mode enabled"
else
    echo "🔍 Assessment mode (use --auto-recover for automatic fixes)"
fi
echo ""

# LaunchD jobs, in boot order. Labels match exactly: io.homelab.compose must
# not pass for io.homelab.compose.immich.
NEED_RECOVERY=false
JOBS_MISSING=false
loaded=$(launchctl list 2>/dev/null || true)
disabled=$(launchctl print-disabled "gui/$(id -u)" 2>/dev/null || true)
echo "📋 LaunchD Jobs:"
for svc in $HOMELAB_SERVICES; do
    label=$(svc_var "$svc" LAUNCHD)
    row=$(awk -v l="$label" '$3 == l' <<<"$loaded")
    if [[ -n "$row" ]]; then
        read -r pid last _ <<<"$row"
        if [[ "$pid" != "-" ]]; then
            echo "  ✅ $label - Running (PID $pid)"
        elif [[ "$last" == "0" ]]; then
            echo "  ✅ $label - Loaded, last exit 0"
        else
            echo "  ⚠️  $label - Loaded, last exit $last"
        fi
    elif grep -qE "\"$label\" => (disabled|true)" <<<"$disabled"; then
        echo "  ⏸️  $label - Held (disabled on purpose)"
    elif [[ "$svc" == "tailscale" && ! -x /opt/homebrew/sbin/tailscaled ]]; then
        echo "  ➖ $label - Not used (the Tailscale app runs its own daemon)"
    else
        echo "  ❌ $label - Not loaded"
        JOBS_MISSING=true
    fi
done
echo ""

# Storage tiers. A tier counts only when a volume is mounted there: an empty
# mount-point folder is not storage, and writing to it fills the internal disk.
echo "💾 Storage Mount Status:"
TIERS_DOWN=""
for tier in $HOMELAB_TIERS; do
    mount=$(homelab_tier_mount "$tier")
    use_var="HOMELAB_TIER_$(upper "$tier")_USE"
    if homelab_is_mounted "$mount"; then
        echo "  ✅ $tier: Mounted - $mount (${!use_var})"
    else
        echo "  ❌ $tier: Not mounted - $mount (${!use_var})"
        TIERS_DOWN="$TIERS_DOWN $tier"
    fi
done
echo ""

# Services: Colima and Docker, then every service with a health URL.
echo "🚀 Service Health:"
COLIMA_OK=false; colima status >/dev/null 2>&1 && COLIMA_OK=true
DOCKER_OK=false; docker info >/dev/null 2>&1 && DOCKER_OK=true
echo "  Colima:   $($COLIMA_OK && echo "✅ Running" || echo "❌ Stopped")"
echo "  Docker:   $($DOCKER_OK && echo "✅ Running" || echo "❌ Stopped")"
DOWN=""
for svc in $HOMELAB_SERVICES; do
    url=$(svc_var "$svc" HEALTH_URL)
    [[ -n "$url" ]] || continue
    expect=$(svc_var "$svc" HEALTH_EXPECT)
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)
    if [[ "$code" == "$expect" ]]; then
        printf '  %-9s ✅ Running (%s)\n' "$svc:" "$url"
    else
        printf '  %-9s ❌ Not answering (%s gave %s)\n' "$svc:" "$url" "${code:-no reply}"
        DOWN="$DOWN $svc"
    fi
done
echo ""

is_down() { [[ " $DOWN " == *" $1 "* ]]; }

if [[ -n "$TIERS_DOWN" ]]; then
    NEED_RECOVERY=true
    echo "🔧 STORAGE: not mounted:$TIERS_DOWN (no automatic fix, by design):"
    echo "  diskutil appleRAID list            # is the RAID set online?"
    echo "  ./diagnostics/check_raid_status.sh"
    echo "  See docs/RECOVERY.md and docs/STORAGE.md"
    echo ""
fi

if $JOBS_MISSING; then
    NEED_RECOVERY=true
    echo "🔧 LAUNCHD: re-render and load the jobs (held jobs stay held):"
    echo "  ./scripts/automation/configure_launchd.sh"
    echo ""
fi

if ! $COLIMA_OK || ! $DOCKER_OK || is_down immich; then
    NEED_RECOVERY=true
    if $AUTO_RECOVER && ! $COLIMA_OK; then
        echo "🐳 EXECUTING DOCKER RECOVERY:"
        echo "  🔄 Starting Colima..."
        if colima start 2>/dev/null; then
            echo "  ✅ Colima started; containers with restart: unless-stopped come back with Docker"
        else
            echo "  ❌ Colima start failed (manual required): ./scripts/infrastructure/start_docker.sh"
        fi
    fi
    # Containers are never deployed from here: core/ doesn't call services/.
    echo "🐳 DOCKER / IMMICH RECOVERY COMMANDS:"
    echo "  ./scripts/infrastructure/start_docker.sh"
    echo "  ./scripts/services/deploy_containers.sh    # $(svc_var immich COMPOSE_DIR)"
    echo ""
fi

if is_down plex; then
    NEED_RECOVERY=true
    app=$(svc_var plex APP)
    if $AUTO_RECOVER; then
        echo "🎬 EXECUTING PLEX RECOVERY:"
        if open -a "$app" 2>/dev/null; then
            echo "  ✅ $app startup initiated"
        else
            echo "  ❌ $app start failed (manual required): open -a '$app'"
        fi
    else
        echo "🎬 PLEX RECOVERY COMMANDS:"
        echo "  open -a '$app'"
    fi
    echo ""
fi

if is_down jellyfin; then
    NEED_RECOVERY=true
    echo "🎞️  JELLYFIN RECOVERY COMMANDS:"
    echo "  open -a '$(svc_var jellyfin APP)'"
    echo ""
fi

if is_down landing; then
    NEED_RECOVERY=true
    label=$(svc_var landing LAUNCHD)
    if $AUTO_RECOVER; then
        echo "🌐 EXECUTING LANDING PAGE RECOVERY:"
        echo "  🔄 Restarting the $label job..."
        # Through LaunchD, not services/ (core/ depends on nothing)
        if launchctl kickstart -k "gui/$(id -u)/$label" 2>/dev/null; then
            echo "  ✅ Landing job restarted (the page is back in about 2.5 minutes)"
        else
            echo "  ❌ Landing job restart failed (manual required): ./scripts/services/enable_landing.sh"
        fi
    else
        echo "🌐 LANDING PAGE RECOVERY COMMANDS:"
        echo "  ./scripts/services/enable_landing.sh"
    fi
    echo ""
fi

if ! $NEED_RECOVERY; then
    echo "🎉 ALL SYSTEMS OPERATIONAL!"
    echo ""
    echo "🔗 Tailnet URLs:"
    ts=$(command -v tailscale || echo /Applications/Tailscale.app/Contents/MacOS/Tailscale)
    # Self comes before Peer, so the first DNSName is this machine's
    host=$("$ts" status --json 2>/dev/null |
        sed -n 's/.*"DNSName": *"\([^"]*\)\.".*/\1/p' | head -1 || true)
    host="${host:-your-device.your-tailnet.ts.net}"
    while read -r port _ service _; do
        [[ -z "${port:-}" || "$port" == \#* ]] && continue
        if [[ "$port" == 443 ]]; then
            echo "  $service: https://$host"
        else
            echo "  $service: https://$host:$port"
        fi
    done <"$HOMELAB_REPO/config/tailscale_serve.txt"
else
    echo "⚠️  RECOVERY NEEDED - Run the commands above to fix issues"
fi

echo ""
echo "📄 Job logs: tail -f $HOMELAB_LAUNCHD_LOG_DIR/homelab-*.{out,err}"
