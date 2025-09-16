#!/usr/bin/env bash
# Configure Plex for direct mount usage (no symlinks)
# Automates the safe configuration changes

set -euo pipefail

echo "=== Configuring Plex for Direct Mounts ==="
echo "$(date): Setting up Plex with direct storage paths"

PLEX_APP_SUPPORT="$HOME/Library/Application Support/Plex Media Server"
PLEX_PREFERENCES="$PLEX_APP_SUPPORT/Preferences.xml"

# Function to setup Plex metadata symlink (only symlink we keep - for Plex's benefit)
setup_plex_metadata() {
    echo "Setting up Plex metadata location..."
    
    # Ensure faststore plex metadata directory exists
    if [[ ! -d "/Volumes/faststore/plex/metadata" ]]; then
        echo "  Creating faststore metadata directory..."
        mkdir -p "/Volumes/faststore/plex/metadata"
        chown $(whoami):staff "/Volumes/faststore/plex/metadata"
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
                mv "$item" "/Volumes/faststore/plex/metadata/"
            fi
        done
        
        # Keep Preferences.xml in place temporarily
        if [[ -f "$PLEX_PREFERENCES" ]]; then
            cp "$PLEX_PREFERENCES" "/Volumes/faststore/plex/metadata/"
        fi
        
        # Create backup of what we moved
        cp -r "/Volumes/faststore/plex/metadata"/* "$BACKUP_DIR/" 2>/dev/null || true
        echo "  ✅ Metadata backed up to: $BACKUP_DIR"
    fi
    
    # Create symlink for Plex metadata (Plex expects this specific location)
    if [[ -L "$PLEX_APP_SUPPORT" ]]; then
        echo "  Removing existing symlink..."
        rm "$PLEX_APP_SUPPORT"
    fi
    
    ln -sf "/Volumes/faststore/plex/metadata" "$PLEX_APP_SUPPORT"
    echo "  ✅ Metadata symlink created: $PLEX_APP_SUPPORT -> /Volumes/faststore/plex/metadata"
}

# Function to create library setup guide
create_library_setup_guide() {
    echo "Creating library setup guide..."
    
    cat > "$HOME/Desktop/PLEX_LIBRARY_SETUP.md" << 'EOF'
# 🎬 Plex Library Setup Guide

After the automated setup, follow these steps to add your media libraries:

## 📋 Library Paths (Direct - No Symlinks)

### 1. Movies Library
- **Path**: `/Volumes/warmstore/movies`
- **Type**: Movies
- **Scanner**: Plex Movie Scanner
- **Agent**: The Movie Database

### 2. TV Shows Library  
- **Path**: `/Volumes/warmstore/tv-shows`
- **Type**: TV Shows
- **Scanner**: Plex Series Scanner
- **Agent**: The Movie Database

### 3. Music Library
- **Path**: `/Volumes/warmstore/music`
- **Type**: Music
- **Scanner**: Plex Music Scanner
- **Agent**: Last.fm

### 4. Collections Library (Optional)
- **Path**: `/Volumes/warmstore/collections`
- **Type**: Movies or TV Shows (depending on content)
- **Scanner**: Plex Movie Scanner or Plex Series Scanner

## 🔧 Steps to Add Libraries

1. Open Plex Web: http://localhost:32400/web
2. Go to **Settings** → **Libraries**
3. Click **Add Library**
4. Choose library type and use the paths above
5. Configure scanner and agent settings
6. Click **Add Library**

## ⚙️ Additional Settings

### Transcoding (Recommended)
- Go to **Settings** → **Transcoder** → **Advanced**
- Set **Transcoder temporary directory**: `/Volumes/faststore/plex/transcoding`
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

    echo "  ✅ Setup guide created: $HOME/Desktop/PLEX_LIBRARY_SETUP.md"
}

# Main execution
main() {
    echo "Starting Plex direct mount configuration..."
    
    # Verify prerequisites
    if [[ ! -d "/Volumes/faststore" ]]; then
        echo "❌ ERROR: /Volumes/faststore not found. Run storage setup first."
        exit 1
    fi
    
    if [[ ! -d "/Volumes/warmstore" ]]; then
        echo "❌ ERROR: /Volumes/warmstore not found. Run storage setup first."
        exit 1
    fi
    
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