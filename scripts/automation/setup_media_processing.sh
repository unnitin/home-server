#!/usr/bin/env bash
set -euo pipefail

# Media Processing Setup - Configures automated media processing for Plex
# Sets up Staging directories, installs dependencies, and configures automation

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
WARMSTORE="/Volumes/warmstore"
STAGING_DIR="$WARMSTORE/Staging"

echo "=== Media Processing Setup ==="
echo

# Check prerequisites
echo "🔍 Checking prerequisites..."

# Check if warmstore exists
if [[ ! -d "$WARMSTORE" ]]; then
    echo "❌ Warmstore directory not found: $WARMSTORE"
    echo "💡 Make sure your RAID storage is mounted"
    exit 1
fi

# Check if we have write permissions
if [[ ! -w "$WARMSTORE" ]]; then
    echo "❌ No write permissions to warmstore: $WARMSTORE"
    echo "💡 Run: sudo chown -R $(whoami):staff $WARMSTORE"
    exit 1
fi

echo "✅ Prerequisites check passed"
echo

# Create staging directories
echo "📁 Setting up Staging directories..."
mkdir -p "$STAGING_DIR"/{Movies,TV\ Shows,Collections,logs,failed}

# Create centralized logging directories
echo "📁 Setting up centralized logging..."
mkdir -p "$WARMSTORE/logs"/{immich,colima,tailscale,updatecheck,media-watcher,powermgmt,storage,plex,landing}

# Set proper permissions
chown -R $(whoami):staff "$STAGING_DIR" "$WARMSTORE/logs" 2>/dev/null || true
chmod -R 755 "$STAGING_DIR" "$WARMSTORE/logs"

echo "✅ Created Staging structure:"
echo "   📂 $STAGING_DIR/Movies"
echo "   📂 $STAGING_DIR/TV Shows"
echo "   📂 $STAGING_DIR/Collections"
echo "   📂 $STAGING_DIR/logs"
echo "   📂 $STAGING_DIR/failed"
echo
echo "✅ Created centralized logging:"
echo "   📂 $WARMSTORE/logs/immich"
echo "   📂 $WARMSTORE/logs/colima"
echo "   📂 $WARMSTORE/logs/tailscale"
echo "   📂 $WARMSTORE/logs/media-watcher"
echo "   📂 $WARMSTORE/logs/... (and others)"
echo

# Check for optional dependencies
echo "🔧 Checking optional dependencies..."

# Check for fswatch (for real-time monitoring)
if command -v fswatch >/dev/null 2>&1; then
    echo "✅ fswatch found - real-time monitoring available"
    FSWATCH_AVAILABLE=true
else
    echo "⚠️  fswatch not found - will use polling mode"
    echo "💡 Install with: brew install fswatch"
    FSWATCH_AVAILABLE=false
fi

# Check for mediainfo (for advanced media analysis)
if command -v mediainfo >/dev/null 2>&1; then
    echo "✅ mediainfo found - enhanced media analysis available"
else
    echo "⚠️  mediainfo not found - basic processing only"
    echo "💡 Install with: brew install mediainfo"
fi

# Check for ffprobe (for media information)
if command -v ffprobe >/dev/null 2>&1; then
    echo "✅ ffprobe found - media validation available"
else
    echo "⚠️  ffprobe not found - limited media validation"
    echo "💡 Install with: brew install ffmpeg"
fi

echo

# Test the media processor
echo "🧪 Testing media processor..."
if "$SCRIPT_DIR/media_processor.sh" --cleanup-only; then
    echo "✅ Media processor test passed"
else
    echo "❌ Media processor test failed"
    exit 1
fi
echo

# Install LaunchD service for automatic monitoring
echo "🚀 Setting up automation..."

# Copy and configure the LaunchD plist
PLIST_SOURCE="$REPO_ROOT/launchd/io.homelab.media.watcher.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/io.homelab.media.watcher.plist"

if [[ -f "$PLIST_SOURCE" ]]; then
    # Replace __HOME__ placeholder with actual home directory
    sed "s|__HOME__|$HOME|g" "$PLIST_SOURCE" > "$PLIST_TARGET"
    
    # Load the service
    launchctl unload "$PLIST_TARGET" 2>/dev/null || true
    if launchctl load "$PLIST_TARGET"; then
        echo "✅ Media watcher LaunchD service installed and loaded"
    else
        echo "❌ Failed to load LaunchD service"
        exit 1
    fi
else
    echo "❌ LaunchD plist not found: $PLIST_SOURCE"
    exit 1
fi

echo

# Show usage information
echo "🎉 Media Processing Setup Complete!"
echo
echo "📋 USAGE:"
echo
echo "1. 📥 DROP FILES:"
echo "   • Movies: $STAGING_DIR/Movies/"
echo "   • TV Shows: $STAGING_DIR/TV Shows/"
echo "   • Collections: $STAGING_DIR/Collections/"
echo
echo "2. 🔄 AUTOMATIC PROCESSING:"
if [[ "$FSWATCH_AVAILABLE" == "true" ]]; then
    echo "   • Files are processed automatically when detected"
    echo "   • Real-time monitoring with fswatch"
else
    echo "   • Files are checked every 60 seconds"
    echo "   • Polling mode (install fswatch for real-time)"
fi
echo
echo "3. 📊 MONITORING:"
echo "   • Media processing logs: $WARMSTORE/logs/media-watcher/"
echo "   • Service logs: $WARMSTORE/logs/{immich,colima,tailscale,etc}/"
echo "   • Failed files: $STAGING_DIR/failed/"
echo "   • Service status: scripts/media_watcher.sh status"
echo
echo "4. 🎯 PLEX NAMING CONVENTIONS:"
echo "   Movies: Movie Name (Year)/Movie Name (Year).ext"
echo "   TV Shows: Show Name (Year)/Season XX/Show Name - sXXeYY.ext"
echo "   Collections: Preserves original folder structure and naming"
echo
echo "📖 MANUAL COMMANDS:"
echo "   • Process now: scripts/media_processor.sh"
echo "   • Movies only: scripts/media_processor.sh --movies-only"
echo "   • TV only: scripts/media_processor.sh --tv-only"
echo "   • Collections only: scripts/media_processor.sh --collections-only"
echo "   • Start watcher: scripts/media_watcher.sh start"
echo "   • Stop watcher: scripts/media_watcher.sh stop"
echo "   • Watcher status: scripts/media_watcher.sh status"
echo
echo "🔧 The media watcher service will start automatically on login."
echo "📁 Drop your media files in the Staging directories and they'll be"
echo "   automatically organized according to Plex naming conventions!"
echo
echo "🧹 AUTOMATIC CLEANUP:"
echo "   • Processed files are moved to target directories"
echo "   • Empty subdirectories are removed"
echo "   • System files (.DS_Store, Thumbs.db) are cleaned up"
echo "   • Main staging directories are preserved for future use"
echo "   • Failed files are moved to Staging/failed/ for review"
echo "   • Logs are kept for 30 days, failed files for 7 days"
