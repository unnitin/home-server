#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Plex Media Server"

# Check if Plex process is running
if pgrep -fl "Plex Media Server" >/dev/null 2>&1; then
    ok "Plex Media Server process running"
    # Show process details
    plex_info=$(pgrep -fl "Plex Media Server" | head -1)
    ok "Process: $plex_info"
else
    fail "Plex Media Server not running"
fi

# Check if Plex web interface is accessible
http_probe "http://localhost:32400/web" || true

# Check LaunchAgent status
if [[ -f "$HOME/Library/LaunchAgents/com.plexapp.plexmediaserver.plist" ]]; then
    ok "LaunchAgent plist exists"
    
    # Check if LaunchAgent is loaded
    if launchctl print "gui/$(id -u)/com.plexapp.plexmediaserver" >/dev/null 2>&1; then
        ok "LaunchAgent loaded and active"
    else
        warn "LaunchAgent not loaded (may need manual start)"
    fi
else
    warn "LaunchAgent plist not found (manual Plex installation?)"
fi

# Check Plex preferences directory
plex_prefs="$HOME/Library/Application Support/Plex Media Server"
if [[ -d "$plex_prefs" ]]; then
    ok "Plex preferences directory exists"
    
    # Check if there are any libraries configured
    if [[ -f "$plex_prefs/Preferences.xml" ]]; then
        ok "Plex configuration file exists"
    else
        warn "Plex not yet configured (no Preferences.xml)"
    fi
else
    warn "Plex preferences directory not found"
fi

# Check for media directories
for media_dir in "/Volumes/warmstore" "/Volumes/faststore"; do
    if [[ -d "$media_dir" ]]; then
        ok "Media directory available: $media_dir"
    else
        warn "Media directory not mounted: $media_dir"
    fi
done

print_summary