#!/usr/bin/env bash
# Install Jellyfin Media Server on macOS
# Uses Homebrew for reliable installation

set -euo pipefail

echo "=== Installing Jellyfin Media Server ==="
echo "$(date): Starting Jellyfin installation"

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"

# Check if Jellyfin is already running
if pgrep -f "Jellyfin Server" >/dev/null 2>&1; then
    echo "⚠️  Jellyfin is already running. Stopping it..."
    killall "Jellyfin Server" 2>/dev/null || true
    killall "jellyfin" 2>/dev/null || true
    sleep 3
fi

# Remove existing Jellyfin.app if present
if [[ -d "/Applications/Jellyfin.app" ]]; then
    echo "Removing existing Jellyfin installation..."
    rm -rf "/Applications/Jellyfin.app"
fi

# Install Jellyfin via Homebrew
echo "Installing Jellyfin via Homebrew..."
if brew install --cask jellyfin; then
    echo "✅ Jellyfin installed successfully via Homebrew"
else
    echo "❌ ERROR: Homebrew installation failed"
    exit 1
fi

# Verify installation
if [[ -d "/Applications/Jellyfin.app" ]]; then
    echo "✅ Jellyfin installation verified"
    echo ""
    echo "📝 Next steps:"
    echo "   1. Run: ./scripts/services/configure_jellyfin.sh"
    echo "   2. Run: ./scripts/services/start_jellyfin_safe.sh"
    echo "   3. Visit: http://localhost:8096"
    echo ""
    echo "📖 Full documentation: docs/JELLYFIN.md"
else
    echo "❌ ERROR: Installation verification failed"
    exit 1
fi

