#!/usr/bin/env bash
set -euo pipefail

# Ensure storage mounts exist and are properly symlinked for interim configuration
echo "$(date): Ensuring storage mount points..."

# Wait for warmstore to be available
WARMSTORE="/Volumes/warmstore"
TIMEOUT=60
COUNT=0

while [[ ! -d "$WARMSTORE" && $COUNT -lt $TIMEOUT ]]; do
    echo "Waiting for $WARMSTORE to be available... ($COUNT/$TIMEOUT)"
    sleep 1
    ((COUNT++))
done

if [[ ! -d "$WARMSTORE" ]]; then
    echo "ERROR: $WARMSTORE not available after $TIMEOUT seconds"
    exit 1
fi

# CRITICAL: Remove any existing circular symlinks inside warmstore directories
echo "Checking for and removing any circular symlinks..."
[[ -L "$WARMSTORE/Movies/Movies" ]] && rm "$WARMSTORE/Movies/Movies" 2>/dev/null && echo "  🧹 Removed circular Movies symlink"
[[ -L "$WARMSTORE/TV Shows/TV Shows" ]] && rm "$WARMSTORE/TV Shows/TV Shows" 2>/dev/null && echo "  🧹 Removed circular TV Shows symlink"
[[ -L "$WARMSTORE/Photos/Photos" ]] && rm "$WARMSTORE/Photos/Photos" 2>/dev/null && echo "  🧹 Removed circular Photos symlink"

# Create Media mount structure (Plex)
echo "Setting up Media mount points..."
if mkdir -p /Volumes/Media 2>/dev/null; then
    # Ensure source directories exist first
    mkdir -p "$WARMSTORE/Movies" "$WARMSTORE/TV Shows" 2>/dev/null
    
    # Remove any existing symlinks to prevent circular references
    [[ -L "/Volumes/Media/Movies" ]] && rm "/Volumes/Media/Movies" 2>/dev/null
    [[ -L "/Volumes/Media/TV" ]] && rm "/Volumes/Media/TV" 2>/dev/null
    
    # Create proper symlinks
    ln -sf "$WARMSTORE/Movies" /Volumes/Media/Movies 2>/dev/null && echo "  ✅ Movies symlink created" || echo "  ⚠️  Movies symlink failed"
    ln -sf "$WARMSTORE/TV Shows" /Volumes/Media/TV 2>/dev/null && echo "  ✅ TV symlink created" || echo "  ⚠️  TV symlink failed"
else
    echo "  ⚠️  Cannot create /Volumes/Media (permission denied)"
fi

# Create Photos mount (Immich) 
echo "Setting up Photos mount point..."
mkdir -p "$WARMSTORE/Photos" 2>/dev/null && echo "  ✅ Photos directory ensured" || echo "  ⚠️  Photos directory failed"
if ln -sf "$WARMSTORE/Photos" /Volumes/Photos 2>/dev/null; then
    echo "  ✅ Photos symlink created"
else
    echo "  ⚠️  Photos symlink failed (permission denied)"
    echo "  💡 Manual fix: sudo ln -sf '$WARMSTORE/Photos' /Volumes/Photos"
fi

# Create Archive placeholder
echo "Setting up Archive placeholder..."
if mkdir -p /Volumes/Archive 2>/dev/null; then
    echo "  ✅ Archive directory created"
else
    echo "  ⚠️  Archive directory failed (permission denied)"
    echo "  💡 Manual fix: sudo mkdir -p /Volumes/Archive"
fi

# Set permissions (best effort)
if chown -R $(whoami):staff /Volumes/Media /Volumes/Photos /Volumes/Archive 2>/dev/null; then
    echo "  ✅ Permissions updated"
else
    echo "  ⚠️  Permission update failed (expected for /Volumes/ operations)"
fi

# Summary and fallback guidance
echo ""
echo "$(date): Storage setup completed with available permissions"

# Check what actually worked
MEDIA_OK=false
PHOTOS_OK=false
ARCHIVE_OK=false

[[ -d "/Volumes/Media" ]] && MEDIA_OK=true
[[ -L "/Volumes/Photos" ]] && PHOTOS_OK=true
[[ -d "/Volumes/Archive" ]] && ARCHIVE_OK=true

echo "📊 Status Summary:"
echo "  Media:   $($MEDIA_OK && echo "✅ Available" || echo "❌ Failed") - /Volumes/Media"
echo "  Photos:  $($PHOTOS_OK && echo "✅ Available" || echo "❌ Failed") - /Volumes/Photos"
echo "  Archive: $($ARCHIVE_OK && echo "✅ Available" || echo "❌ Failed") - /Volumes/Archive"

# Provide fallback strategies
if ! $PHOTOS_OK || ! $ARCHIVE_OK; then
    echo ""
    echo "🚨 FALLBACK STRATEGY - Some operations need manual intervention:"
    echo ""
    
    if ! $PHOTOS_OK; then
        echo "📸 IMMICH PHOTOS FALLBACK:"
        echo "   • Immich can use: $WARMSTORE/Photos (direct path)"
        echo "   • Manual fix: sudo ln -sf '$WARMSTORE/Photos' /Volumes/Photos"
        echo "   • Or update Immich config to use warmstore path directly"
    fi
    
    if ! $ARCHIVE_OK; then
        echo "📦 ARCHIVE STORAGE FALLBACK:"
        echo "   • Use warmstore for now: $WARMSTORE/Archive"
        echo "   • Manual fix: sudo mkdir -p /Volumes/Archive"
        echo "   • Set up when coldstore drives are available"
    fi
    
    echo ""
    echo "🔧 QUICK MANUAL RECOVERY:"
    echo "   sudo ln -sf '$WARMSTORE/Photos' /Volumes/Photos"
    echo "   sudo mkdir -p /Volumes/Archive"
    echo ""
fi

echo "✅ Automated setup complete - services can start"

