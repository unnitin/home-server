#!/usr/bin/env bash
# Configure Plex for direct mount usage (no symlinks)
# Automates the safe configuration changes

set -euo pipefail

echo "=== Configuring Plex for Direct Mounts ==="
echo "$(date): Setting up Plex with direct storage paths"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/environment.sh
source "$SCRIPT_DIR/../core/environment.sh"
PLEX_METADATA="$HOMELAB_SVC_PLEX_DATA_DIR/metadata"   # from the manifest

PLEX_APP_SUPPORT="$HOME/Library/Application Support/Plex Media Server"
PLEX_PREFERENCES="$PLEX_APP_SUPPORT/Preferences.xml"

# Function to setup Plex metadata symlink (only symlink we keep - for Plex's benefit)
setup_plex_metadata() {
    echo "Setting up Plex metadata location..."

    # Ensure faststore plex metadata directory exists
    if [[ ! -d "$PLEX_METADATA" ]]; then
        echo "  Creating faststore metadata directory..."
        mkdir -p "$PLEX_METADATA"
        chown "$(whoami)":staff "$PLEX_METADATA"
    fi

    # Handle existing metadata
    if [[ -d "$PLEX_APP_SUPPORT" && ! -L "$PLEX_APP_SUPPORT" ]]; then
        echo "  Moving existing metadata to faststore..."

        # Create backup location
        BACKUP_DIR="$HOME/Desktop/plex_metadata_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"

        # Move existing metadata (excluding Preferences.xml temporarily)
        for item in "$PLEX_APP_SUPPORT"/*; do
            if [[ -e "$item" && "$(basename "$item")" != "Preferences.xml" ]]; then
                echo "    Moving $(basename "$item")..."
                mv "$item" "$PLEX_METADATA/"
            fi
        done

        # Keep Preferences.xml in place temporarily
        if [[ -f "$PLEX_PREFERENCES" ]]; then
            cp "$PLEX_PREFERENCES" "$PLEX_METADATA/"
        fi

        # Create backup of what we moved
        cp -r "$PLEX_METADATA"/* "$BACKUP_DIR/" 2>/dev/null || true
        echo "  ✅ Metadata backed up to: $BACKUP_DIR"
    fi

    # Create symlink for Plex metadata (Plex expects this specific location)
    if [[ -L "$PLEX_APP_SUPPORT" ]]; then
        echo "  Removing existing symlink..."
        rm "$PLEX_APP_SUPPORT"
    fi

    ln -sf "$PLEX_METADATA" "$PLEX_APP_SUPPORT"
    echo "  ✅ Metadata symlink created: $PLEX_APP_SUPPORT -> $PLEX_METADATA"
}

# Function to create library setup guide
create_library_setup_guide() {
    echo "Creating library setup guide..."

    cat > "$HOME/Desktop/PLEX_LIBRARY_SETUP.md" << 'EOF'
# 🎬 Plex Library Setup Guide

After the automated setup, follow these steps to add your media libraries:

## 📋 Library Paths (Direct - No Symlinks)

### 1. Movies Library
- **Path**: `@MOVIES_DIR@`
- **Type**: Movies
- **Scanner**: Plex Movie Scanner
- **Agent**: The Movie Database

### 2. TV Shows Library
- **Path**: `@TV_DIR@`
- **Type**: TV Shows
- **Scanner**: Plex Series Scanner
- **Agent**: The Movie Database

### 3. Music Library
- **Path**: `@MEDIA_ROOT@/music`
- **Type**: Music
- **Scanner**: Plex Music Scanner
- **Agent**: Last.fm

### 4. Collections Library (Optional)
- **Path**: `@COLLECTIONS_DIR@`
- **Type**: Movies or TV Shows (depending on content)
- **Scanner**: Plex Movie Scanner or Plex Series Scanner

## 🔧 Steps to Add Libraries

1. Open Plex Web: http://localhost:@PLEX_PORT@/web
2. Go to **Settings** → **Libraries**
3. Click **Add Library**
4. Choose library type and use the paths above
5. Configure scanner and agent settings
6. Click **Add Library**

## ⚙️ Additional Settings

### Transcoding (Recommended)
- Go to **Settings** → **Transcoder** → **Advanced**
- Set **Transcoder temporary directory**: `@PLEX_DATA_DIR@/transcoding`
- Enable **Use hardware acceleration when available** (if supported)

### Performance Tips
- Enable "Empty trash automatically after every scan"
- Set thumbnail quality based on your preference
- Configure remote access for Tailscale usage

## 📱 Mobile App Setup
- Server will auto-discover on local network
- For remote access: Use Tailscale hostname:32400
- Example: `your-device.your-tailnet.ts.net:32400`
EOF
    # The guide is written verbatim (it's Markdown, full of backticks); fill in the
    # manifest's paths afterwards
    sed -i '' \
        -e "s|@MOVIES_DIR@|$HOMELAB_MEDIA_MOVIES_DIR|g" \
        -e "s|@TV_DIR@|$HOMELAB_MEDIA_TV_DIR|g" \
        -e "s|@COLLECTIONS_DIR@|$HOMELAB_MEDIA_COLLECTIONS_DIR|g" \
        -e "s|@MEDIA_ROOT@|$HOMELAB_MEDIA_ROOT|g" \
        -e "s|@PLEX_DATA_DIR@|$HOMELAB_SVC_PLEX_DATA_DIR|g" \
        -e "s|@PLEX_PORT@|${HOMELAB_SVC_PLEX_PORTS%% *}|g" \
        "$HOME/Desktop/PLEX_LIBRARY_SETUP.md"

    echo "  ✅ Setup guide created: $HOME/Desktop/PLEX_LIBRARY_SETUP.md"
}

# Main execution
main() {
    echo "Starting Plex direct mount configuration..."

    # Verify prerequisites
    # Really mounted, by diskutil's account: an empty mount-point folder isn't (D22),
    # and moving Plex's data into one would put it back on the internal disk
    local tier mount
    for tier in "$HOMELAB_SVC_PLEX_DATA_TIER" "${HOMELAB_MEDIA_ROOT##*/}"; do
        mount="$(homelab_tier_mount "$tier")"
        if ! homelab_is_mounted "$mount"; then
            echo "❌ ERROR: $mount not mounted. Check the storage first (diskutil appleRAID list)."
            exit 1
        fi
    done

    # Execute configuration steps
    setup_plex_metadata
    create_library_setup_guide

    echo ""
    echo "✅ Plex direct mount configuration complete!"
    echo ""
    echo "📝 Next steps:"
    echo "  1. Start Plex Media Server"
    echo "  2. Follow the guide: ~/Desktop/PLEX_LIBRARY_SETUP.md"
    echo "  3. Add libraries using the direct paths (no symlinks)"
    echo ""
    echo "🚀 Starting Plex now..."
    open -a "Plex Media Server" 2>/dev/null || echo "  (Install Plex first if needed)"
}

main "$@"
