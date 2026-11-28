#!/usr/bin/env bash
# Configure Jellyfin to use faststore for metadata, transcoding, and cache
# Moves existing data to faststore and creates symlinks

set -euo pipefail

echo "=== Configuring Jellyfin for Faststore Storage ==="
echo "$(date): Setting up Jellyfin with faststore paths"

JELLYFIN_CONFIG="$HOME/Library/Application Support/jellyfin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"
FASTSTORE_JELLYFIN="$HOMELAB_SVC_JELLYFIN_DATA_DIR"   # from the manifest
DATA_MOUNT="$(homelab_tier_mount "$HOMELAB_SVC_JELLYFIN_DATA_TIER")"

# Verify the data tier is really mounted: an empty mount-point folder isn't (D22)
if ! homelab_is_mounted "$DATA_MOUNT"; then
    echo "❌ ERROR: $DATA_MOUNT not mounted"
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

# No chown -R: the folders above are yours already, and a recursive chown would
# rewrite the owner of every file Jellyfin has (D22)

echo "✅ Jellyfin configuration complete!"
echo ""
echo "📋 Storage Configuration:"
echo "   Config:      $FASTSTORE_JELLYFIN/config"
echo "   Cache:       $FASTSTORE_JELLYFIN/cache"
echo "   Transcoding: $FASTSTORE_JELLYFIN/transcoding"
echo "   Logs:        $FASTSTORE_JELLYFIN/logs"
echo ""
echo "📁 Media Libraries:"
echo "   Movies:   $HOMELAB_MEDIA_MOVIES_DIR"
echo "   TV Shows: $HOMELAB_MEDIA_TV_DIR"
echo ""
echo "📖 Full documentation: docs/JELLYFIN.md"
echo ""
echo "Next steps:"
echo "  1. Start Jellyfin: ./scripts/services/start_jellyfin_safe.sh"
echo "  2. Access web UI: http://localhost:$HOMELAB_SVC_JELLYFIN_PORTS"
echo "  3. Follow setup guide in docs/JELLYFIN.md"
