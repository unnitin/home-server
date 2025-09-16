#!/usr/bin/env bash
# Storage Usage Monitor for Home Server
# Checks storage usage and alerts if thresholds are exceeded

set -euo pipefail

# Configuration
FASTSTORE_PATH="/Volumes/faststore"
WARMSTORE_PATH="/Volumes/warmstore"
WARNING_THRESHOLD=80
CRITICAL_THRESHOLD=90

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo "🔍 Home Server Storage Usage Report"
echo "=================================="
echo ""

# Check faststore (Immich photos)
if [ -d "$FASTSTORE_PATH" ]; then
    FASTSTORE_USAGE=$(df "$FASTSTORE_PATH" | tail -1 | awk '{print $5}' | sed 's/%//')
    FASTSTORE_SIZE=$(df -h "$FASTSTORE_PATH" | tail -1 | awk '{print $2}')
    FASTSTORE_USED=$(df -h "$FASTSTORE_PATH" | tail -1 | awk '{print $3}')
    FASTSTORE_AVAIL=$(df -h "$FASTSTORE_PATH" | tail -1 | awk '{print $4}')
    
    echo "📸 Faststore (Immich Photos):"
    echo "  Size: $FASTSTORE_SIZE | Used: $FASTSTORE_USED | Available: $FASTSTORE_AVAIL"
    echo "  Usage: ${FASTSTORE_USAGE}%"
    
    if [ "$FASTSTORE_USAGE" -ge "$CRITICAL_THRESHOLD" ]; then
        echo "  Status: ${RED}CRITICAL${NC} - Usage above ${CRITICAL_THRESHOLD}%"
    elif [ "$FASTSTORE_USAGE" -ge "$WARNING_THRESHOLD" ]; then
        echo "  Status: ${YELLOW}WARNING${NC} - Usage above ${WARNING_THRESHOLD}%"
    else
        echo "  Status: ${GREEN}OK${NC}"
    fi
    echo ""
else
    echo "❌ Faststore not mounted: $FASTSTORE_PATH"
    echo ""
fi

# Check warmstore (Plex media)
if [ -d "$WARMSTORE_PATH" ]; then
    WARMSTORE_USAGE=$(df "$WARMSTORE_PATH" | tail -1 | awk '{print $5}' | sed 's/%//')
    WARMSTORE_SIZE=$(df -h "$WARMSTORE_PATH" | tail -1 | awk '{print $2}')
    WARMSTORE_USED=$(df -h "$WARMSTORE_PATH" | tail -1 | awk '{print $3}')
    WARMSTORE_AVAIL=$(df -h "$WARMSTORE_PATH" | tail -1 | awk '{print $4}')
    
    echo "🎬 Warmstore (Plex Media):"
    echo "  Size: $WARMSTORE_SIZE | Used: $WARMSTORE_USED | Available: $WARMSTORE_AVAIL"
    echo "  Usage: ${WARMSTORE_USAGE}%"
    
    if [ "$WARMSTORE_USAGE" -ge "$CRITICAL_THRESHOLD" ]; then
        echo "  Status: ${RED}CRITICAL${NC} - Usage above ${CRITICAL_THRESHOLD}%"
    elif [ "$WARMSTORE_USAGE" -ge "$WARNING_THRESHOLD" ]; then
        echo "  Status: ${YELLOW}WARNING${NC} - Usage above ${WARNING_THRESHOLD}%"
    else
        echo "  Status: ${GREEN}OK${NC}"
    fi
    echo ""
else
    echo "❌ Warmstore not mounted: $WARMSTORE_PATH"
    echo ""
fi

# Check Immich directory specifically
if [ -d "$FASTSTORE_PATH/immich" ]; then
    IMMICH_SIZE=$(du -sh "$FASTSTORE_PATH/immich" | awk '{print $1}')
    echo "📁 Immich Directory Size: $IMMICH_SIZE"
    echo ""
fi

# Summary
echo "📊 Summary:"
if [ "$FASTSTORE_USAGE" -ge "$WARNING_THRESHOLD" ] || [ "$WARMSTORE_USAGE" -ge "$WARNING_THRESHOLD" ]; then
    echo "⚠️  Storage usage is high - consider cleanup or expansion"
else
    echo "✅ Storage usage is within normal limits"
fi

echo ""
echo "💡 Tips:"
echo "  - Run this script regularly to monitor usage"
echo "  - Consider setting up automated alerts"
echo "  - Clean up old media files if usage gets high"
