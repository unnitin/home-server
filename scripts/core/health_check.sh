#!/usr/bin/env bash
set -euo pipefail

# Post-boot health check with automated recovery
# This script provides comprehensive system assessment and guided recovery

# Common logging functions for use by other modules
log_info() {
    echo "ℹ️  $*"
}

log_warn() {
    echo "⚠️  $*" >&2
}

log_error() {
    echo "❌ $*" >&2
}

# Support automatic recovery mode
AUTO_RECOVER=false
if [[ "${1:-}" == "--auto-recover" ]]; then
    AUTO_RECOVER=true
    shift
fi

echo "🏥 System Health Check & Recovery"
echo "================================"
if $AUTO_RECOVER; then
    echo "🚀 Auto-recovery mode enabled"
else
    echo "🔍 Assessment mode (use --auto-recover for automatic fixes)"
fi
echo ""

# Check LaunchD services
echo "📋 LaunchD Services Status:"
services=(storage colima compose.immich plex landing tailscale updatecheck)
for service in "${services[@]}"; do
    if launchctl list | grep -q "io.homelab.$service"; then
        echo "  ✅ io.homelab.$service - Running"
    else
        echo "  ❌ io.homelab.$service - Not loaded"
    fi
done
echo ""

# Check storage mounts
echo "💾 Storage Mount Status:"
MEDIA_OK=false; [[ -d "/Volumes/Media" ]] && MEDIA_OK=true
PHOTOS_OK=false; [[ -L "/Volumes/Photos" ]] && PHOTOS_OK=true  
ARCHIVE_OK=false; [[ -d "/Volumes/Archive" ]] && ARCHIVE_OK=true

echo "  Media:   $($MEDIA_OK && echo "✅ Available" || echo "❌ Missing") - /Volumes/Media"
echo "  Photos:  $($PHOTOS_OK && echo "✅ Available" || echo "❌ Missing") - /Volumes/Photos"
echo "  Archive: $($ARCHIVE_OK && echo "✅ Available" || echo "❌ Missing") - /Volumes/Archive"
echo ""

# Check running services
echo "🚀 Service Health:"
COLIMA_OK=false; colima status >/dev/null 2>&1 && COLIMA_OK=true
DOCKER_OK=false; docker ps >/dev/null 2>&1 && DOCKER_OK=true
PLEX_OK=false; curl -s http://localhost:32400/identity >/dev/null 2>&1 && PLEX_OK=true
LANDING_OK=false; lsof -i :8080 >/dev/null 2>&1 && LANDING_OK=true

echo "  Colima:  $($COLIMA_OK && echo "✅ Running" || echo "❌ Stopped")"
echo "  Docker:  $($DOCKER_OK && echo "✅ Running" || echo "❌ Stopped")"
echo "  Plex:    $($PLEX_OK && echo "✅ Running" || echo "❌ Stopped")"
echo "  Landing: $($LANDING_OK && echo "✅ Running" || echo "❌ Stopped")"
echo ""

# Storage Recovery (Automated or Manual)
NEED_RECOVERY=false
STORAGE_FIXED=false

if ! $PHOTOS_OK || ! $ARCHIVE_OK; then
    NEED_RECOVERY=true
    if $AUTO_RECOVER; then
        echo "🔧 EXECUTING STORAGE RECOVERY:"
        if ! $PHOTOS_OK; then
            if sudo ln -sf /Volumes/warmstore/Photos /Volumes/Photos 2>/dev/null; then
                echo "  ✅ Photos symlink created"
                STORAGE_FIXED=true
            else
                echo "  ❌ Photos symlink failed (manual required): sudo ln -sf /Volumes/warmstore/Photos /Volumes/Photos"
            fi
        fi
        if ! $ARCHIVE_OK; then
            if sudo mkdir -p /Volumes/Archive 2>/dev/null; then
                echo "  ✅ Archive directory created"
                STORAGE_FIXED=true
            else
                echo "  ❌ Archive directory failed (manual required): sudo mkdir -p /Volumes/Archive"
            fi
        fi
    else
        echo "🔧 STORAGE RECOVERY COMMANDS:"
        ! $PHOTOS_OK && echo "  sudo ln -sf /Volumes/warmstore/Photos /Volumes/Photos"
        ! $ARCHIVE_OK && echo "  sudo mkdir -p /Volumes/Archive"
    fi
    echo ""
fi

if ! $COLIMA_OK || ! $DOCKER_OK; then
    NEED_RECOVERY=true
    if $AUTO_RECOVER; then
        echo "🐳 EXECUTING DOCKER RECOVERY:"
        if ! $COLIMA_OK; then
            echo "  🔄 Starting Colima..."
            if colima start 2>/dev/null; then
                echo "  ✅ Colima started successfully"
                sleep 5  # Give Colima time to fully start
            else
                echo "  ❌ Colima start failed (manual required): colima start"
            fi
        fi
        if docker ps >/dev/null 2>&1; then
            echo "  🔄 Deploying Docker services..."
            if "$(dirname "$0")/30_deploy_services.sh" >/dev/null 2>&1; then
                echo "  ✅ Docker services deployed"
            else
                echo "  ❌ Service deployment failed (manual required): ./scripts/services/deploy_containers.sh"
            fi
        fi
    else
        echo "🐳 DOCKER RECOVERY COMMANDS:"
        echo "  colima start"
        echo "  cd ~/Documents/home-server && ./scripts/services/deploy_containers.sh"
    fi
    echo ""
fi

if ! $PLEX_OK; then
    NEED_RECOVERY=true
    if $AUTO_RECOVER; then
        echo "🎬 EXECUTING PLEX RECOVERY:"
        echo "  🔄 Starting Plex Media Server..."
        if open "/Applications/Plex Media Server.app" 2>/dev/null; then
            echo "  ✅ Plex startup initiated"
        else
            echo "  ❌ Plex start failed (manual required): open '/Applications/Plex Media Server.app'"
        fi
    else
        echo "🎬 PLEX RECOVERY COMMANDS:"
        echo "  open '/Applications/Plex Media Server.app'"
    fi
    echo ""
fi

if ! $LANDING_OK; then
    NEED_RECOVERY=true
    if $AUTO_RECOVER; then
        echo "🌐 EXECUTING LANDING PAGE RECOVERY:"
        echo "  🔄 Starting landing page and HTTPS..."
        if "$(dirname "$0")/37_enable_simple_landing.sh" >/dev/null 2>&1; then
            echo "  ✅ Landing page recovery completed"
        else
            echo "  ❌ Landing page failed (manual required): ./scripts/services/enable_landing.sh"
        fi
    else
        echo "🌐 LANDING PAGE RECOVERY COMMANDS:"
        echo "  cd ~/Documents/home-server && ./scripts/services/enable_landing.sh"
    fi
    echo ""
fi

if ! $NEED_RECOVERY; then
    echo "🎉 ALL SYSTEMS OPERATIONAL!"
    echo ""
    echo "🔗 Access URLs:"
    hostname=$(tailscale status --json 2>/dev/null | grep '"DNSName"' | head -1 | cut -d'"' -f4 | sed 's/\.$//' || echo "your-device.your-tailnet.ts.net")
    echo "  Landing: https://$hostname"
    echo "  Immich:  https://$hostname:2283" 
    echo "  Plex:    https://$hostname:32400"
else
    echo "🚨 RECOVERY COMMANDS SUMMARY:"
    echo "================================"
    echo ""
    echo "🐳 Docker/Colima Issues:"
    echo "  colima start --cpu 4 --memory 8"
    echo "  docker compose -f services/immich/docker-compose.yml up -d"
    echo ""
    echo "🔧 LaunchD Service Issues:"
    echo "  launchctl load ~/Library/LaunchAgents/io.homelab.*.plist"
    echo "  launchctl start io.homelab.colima"
    echo ""
    echo "💾 Storage Issues:"
    echo "  sudo ./scripts/storage/setup_direct_mounts.sh"
    echo "  ./scripts/storage/wait_for_storage.sh"
    echo ""
    echo "⚠️  RECOVERY NEEDED - Run the commands above to fix issues"
fi

echo ""
echo "📄 Check detailed logs: tail -f /tmp/{storage,colima,immich,plex,landing}.{out,err}"
