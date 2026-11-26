#!/usr/bin/env bash
set -euo pipefail

# Media processing setup: the staging folders, the optional tools, and the media
# watcher's LaunchD job. Folders and paths come from the manifest
# (config/homelab.yaml); the work is done by the scripts that own it:
#   scripts/storage/setup_direct_mounts.sh   the folders (mounted tiers only, no sudo)
#   scripts/automation/configure_launchd.sh  the job (rendered from its template)
#
# Usage: ./scripts/automation/setup_media_processing.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"

echo "=== Media Processing Setup ==="
echo

# The media tier must really be mounted: an empty mount-point folder isn't (D22),
# and staging folders made in one would land on the internal disk
echo "🔍 Checking that the media tier is mounted..."
if ! homelab_is_mounted "$HOMELAB_MEDIA_ROOT"; then
    echo "❌ $HOMELAB_MEDIA_ROOT is not mounted. Check the storage first: diskutil appleRAID list"
    exit 1
fi
echo "✅ $HOMELAB_MEDIA_ROOT is mounted"
echo

echo "📁 Creating the media folders..."
"$HOMELAB_REPO/scripts/storage/setup_direct_mounts.sh"
echo

echo "🔧 Checking optional tools..."
if command -v fswatch >/dev/null 2>&1; then
    echo "✅ fswatch found - real-time monitoring"
    FSWATCH_AVAILABLE=true
else
    echo "⚠️  fswatch not found - the watcher will poll (brew install fswatch)"
    FSWATCH_AVAILABLE=false
fi
command -v mediainfo >/dev/null 2>&1 && echo "✅ mediainfo found" ||
    echo "⚠️  mediainfo not found - basic processing only (brew install mediainfo)"
command -v ffprobe >/dev/null 2>&1 && echo "✅ ffprobe found" ||
    echo "⚠️  ffprobe not found - limited media validation (brew install ffmpeg)"
echo

echo "🚀 Installing the media watcher's LaunchD job..."
"$HOMELAB_REPO/scripts/automation/configure_launchd.sh" media.watcher
echo

echo "🎉 Media Processing Setup Complete!"
echo
echo "📥 Drop files in:"
echo "   • Movies:      $HOMELAB_MEDIA_MOVIES_STAGING/"
echo "   • TV Shows:    $HOMELAB_MEDIA_TV_STAGING/"
echo "   • Collections: $HOMELAB_MEDIA_COLLECTIONS_STAGING/"
if $FSWATCH_AVAILABLE; then
    echo "   Files are processed as soon as they're detected (fswatch)."
else
    echo "   Files are checked every 60 seconds (polling; install fswatch for real time)."
fi
echo
echo "📊 Monitoring:"
echo "   • Processing logs: $HOMELAB_LOG_ROOT/media-watcher/"
echo "   • Failed files:    $HOMELAB_MEDIA_FAILED/"
echo "   • Watcher status:  ./scripts/media/watcher.sh status"
echo
echo "📖 By hand:"
echo "   • Process now:       ./scripts/media/processor.sh"
echo "   • One kind only:     ./scripts/media/processor.sh --movies-only | --tv-only | --collections-only"
echo "   • Start/stop watcher: ./scripts/media/watcher.sh start | stop"
