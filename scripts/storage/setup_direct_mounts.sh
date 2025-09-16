#!/usr/bin/env bash
# Setup direct mount directory structure (no symlinks)
# Creates logical data organization within each storage tier

set -euo pipefail

echo "=== Setting up Direct Mount Structure ==="
echo "$(date): Creating clean directory structure without symlinks"

# Function to create directory structure safely
create_structure() {
    local base_path="$1"
    local description="$2"
    shift 2
    local directories=("$@")
    
    if [[ -d "$base_path" ]]; then
        echo "Creating $description structure in $base_path..."
        for dir in "${directories[@]}"; do
            sudo mkdir -p "$base_path/$dir"
            echo "  ✅ Created: $base_path/$dir"
        done
    else
        echo "❌ ERROR: $base_path not found, cannot create $description structure"
        echo "💡 Try: Check if RAID arrays are mounted with 'diskutil list'"
        return 1
    fi
}

# Create faststore directory structure (NVMe - High IOPS)
FASTSTORE_DIRS=(
    "immich"
    "immich/library"
    "immich/upload" 
    "immich/thumbs"
    "immich/encoded-video"
    "immich/database"
    "immich/logs"
    "plex"
    "plex/metadata"
    "plex/transcoding"
    "plex/processing"
    "plex/logs"
)

if ! create_structure "/Volumes/faststore" "faststore (NVMe)" "${FASTSTORE_DIRS[@]}"; then
    echo "❌ Failed to create faststore directory structure"
    echo "💡 Try: Ensure /Volumes/faststore is mounted before running this script"
fi

# Create warmstore directory structure (SSD - Sequential storage)
WARMSTORE_DIRS=(
    "movies"
    "tv-shows" 
    "music"
    "collections"
    "staging"
    "staging/movies"
    "staging/tv-shows"
    "staging/collections"
    "logs"
    "logs/system"
    "logs/media-processing"
    "logs/web"
)

if ! create_structure "/Volumes/warmstore" "warmstore (SSD)" "${WARMSTORE_DIRS[@]}"; then
    echo "❌ Failed to create warmstore directory structure"
    echo "💡 Try: Ensure /Volumes/warmstore is mounted before running this script"
fi

# Set proper permissions (only on our application directories)
echo "Setting permissions..."
echo "  Setting ownership on application directories..."

# Faststore directories
for dir in /Volumes/faststore/immich /Volumes/faststore/plex; do
    if [ -d "$dir" ]; then
        if sudo chown -R $(whoami):staff "$dir" 2>/dev/null; then
            echo "    ✅ Ownership set: $dir"
        else
            echo "    ⚠️  Could not set ownership: $dir"
        fi
    fi
done

# Warmstore directories
for dir in /Volumes/warmstore/movies /Volumes/warmstore/tv-shows /Volumes/warmstore/music /Volumes/warmstore/collections /Volumes/warmstore/staging /Volumes/warmstore/logs; do
    if [ -d "$dir" ]; then
        # Check if directory has existing data (more than just .DS_Store)
        file_count=$(find "$dir" -type f ! -name ".DS_Store" 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            echo "    ℹ️  Skipping ownership change (has data): $dir"
        else
            if sudo chown -R $(whoami):staff "$dir" 2>/dev/null; then
                echo "    ✅ Ownership set: $dir"
            else
                echo "    ⚠️  Could not set ownership: $dir"
            fi
        fi
    fi
done

echo "  Setting permissions on application directories..."

# Faststore permissions
for dir in /Volumes/faststore/immich /Volumes/faststore/plex; do
    if [ -d "$dir" ]; then
        if sudo chmod -R 755 "$dir" 2>/dev/null; then
            echo "    ✅ Permissions set: $dir"
        else
            echo "    ⚠️  Could not set permissions: $dir"
        fi
    fi
done

# Warmstore permissions
for dir in /Volumes/warmstore/movies /Volumes/warmstore/tv-shows /Volumes/warmstore/music /Volumes/warmstore/collections /Volumes/warmstore/staging /Volumes/warmstore/logs; do
    if [ -d "$dir" ]; then
        # Check if directory has existing data (more than just .DS_Store)
        file_count=$(find "$dir" -type f ! -name ".DS_Store" 2>/dev/null | wc -l)
        if [ "$file_count" -gt 0 ]; then
            echo "    ℹ️  Skipping permission change (has data): $dir"
        else
            if sudo chmod -R 755 "$dir" 2>/dev/null; then
                echo "    ✅ Permissions set: $dir"
            else
                echo "    ⚠️  Could not set permissions: $dir"
            fi
        fi
    fi
done

# Summary
echo ""
echo "=== Direct Mount Structure Summary ==="
echo "📊 Faststore (NVMe - High IOPS):"
[[ -d "/Volumes/faststore" ]] && find /Volumes/faststore -type d -maxdepth 2 2>/dev/null | grep -v "\.Spotlight-V100\|\.fseventsd" | sort | sed 's/^/  /' || true

echo ""
echo "📊 Warmstore (SSD - Sequential):"  
[[ -d "/Volumes/warmstore" ]] && find /Volumes/warmstore -type d -maxdepth 2 2>/dev/null | sort | sed 's/^/  /' || true

echo ""
echo "✅ Direct mount structure setup complete!"
echo "🎯 Services can now use direct paths without symlinks"
echo ""
echo "📝 Next steps:"
echo "  1. Configure Plex libraries to use /Volumes/warmstore/* paths"
echo "  2. Verify Immich uses /Volumes/faststore/immich path"
echo "  3. Update Plex metadata location to /Volumes/faststore/plex/metadata"