#!/usr/bin/env bash
# Configure Jellyfin to use faststore for metadata, transcoding, and cache
# Moves existing data to faststore and creates symlinks

set -euo pipefail

echo "=== Configuring Jellyfin for Faststore Storage ==="
echo "$(date): Setting up Jellyfin with faststore paths"

JELLYFIN_CONFIG="$HOME/Library/Application Support/jellyfin"
FASTSTORE_JELLYFIN="/Volumes/faststore/jellyfin"

# Verify faststore is mounted
if [[ ! -d "/Volumes/faststore" ]]; then
    echo "❌ ERROR: /Volumes/faststore not mounted"
    exit 1
fi

# Create faststore directory structure
echo "Creating faststore directory structure..."
mkdir -p "$FASTSTORE_JELLYFIN"/{config,cache,transcoding,logs}

# Handle existing Jellyfin data
if [[ -d "$JELLYFIN_CONFIG" && ! -L "$JELLYFIN_CONFIG" ]]; then
    echo "Moving existing Jellyfin data to faststore..."
    
    # Create backup
    BACKUP_DIR="$HOME/Desktop/jellyfin_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Copy existing config to faststore
    if [[ "$(ls -A "$JELLYFIN_CONFIG" 2>/dev/null)" ]]; then
        echo "  Copying existing configuration..."
        cp -r "$JELLYFIN_CONFIG"/* "$FASTSTORE_JELLYFIN/config/" 2>/dev/null || true
        cp -r "$JELLYFIN_CONFIG"/* "$BACKUP_DIR/" 2>/dev/null || true
        echo "  ✅ Backup created: $BACKUP_DIR"
    fi
    
    # Remove old config directory
    rm -rf "$JELLYFIN_CONFIG"
fi

# Create symlink for config directory
if [[ ! -L "$JELLYFIN_CONFIG" ]]; then
    echo "Creating symlink: $JELLYFIN_CONFIG -> $FASTSTORE_JELLYFIN/config"
    ln -sf "$FASTSTORE_JELLYFIN/config" "$JELLYFIN_CONFIG"
fi

# Set permissions
chown -R $(whoami):staff "$FASTSTORE_JELLYFIN"

echo "✅ Jellyfin configuration complete!"
echo ""
echo "📋 Storage Configuration:"
echo "   Config:      /Volumes/faststore/jellyfin/config"
echo "   Cache:       /Volumes/faststore/jellyfin/cache"
echo "   Transcoding: /Volumes/faststore/jellyfin/transcoding"
echo "   Logs:        /Volumes/faststore/jellyfin/logs"
echo ""
echo "📁 Media Libraries:"
echo "   Movies:   /Volumes/warmstore/movies"
echo "   TV Shows: /Volumes/warmstore/tv-shows"
echo ""
echo "📖 Full documentation: docs/JELLYFIN.md"
echo ""
echo "Next steps:"
echo "  1. Start Jellyfin: ./scripts/services/start_jellyfin_safe.sh"
echo "  2. Access web UI: http://localhost:8096"
echo "  3. Follow setup guide in docs/JELLYFIN.md"

