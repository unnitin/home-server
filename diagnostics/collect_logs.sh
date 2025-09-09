#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="/tmp/homeserver-logs-$TIMESTAMP"
ARCHIVE_FILE="/tmp/homeserver-logs-$TIMESTAMP.tgz"

section "Log Collection"

# Create temporary directory for logs
mkdir -p "$OUTPUT_DIR"
ok "Created log collection directory: $OUTPUT_DIR"

# Function to safely copy files
safe_copy() {
    local source="$1"
    local dest="$2"
    local description="$3"
    
    if [[ -f "$source" ]]; then
        cp "$source" "$dest" 2>/dev/null && ok "Collected: $description" || warn "Failed to copy: $description"
    elif [[ -d "$source" ]]; then
        cp -r "$source" "$dest" 2>/dev/null && ok "Collected: $description" || warn "Failed to copy: $description"  
    else
        warn "Not found: $description ($source)"
    fi
}

# Function to capture command output
capture_command() {
    local command="$1"
    local output_file="$2"
    local description="$3"
    
    if eval "$command" > "$output_file" 2>&1; then
        ok "Captured: $description"
    else
        warn "Failed to capture: $description"
    fi
}

# Collect basic system info
capture_command "date" "$OUTPUT_DIR/timestamp.txt" "System timestamp"
capture_command "sw_vers" "$OUTPUT_DIR/macos_version.txt" "macOS version"
capture_command "system_profiler SPHardwareDataType" "$OUTPUT_DIR/hardware_info.txt" "Hardware information"
capture_command "df -h" "$OUTPUT_DIR/disk_usage.txt" "Disk usage"
capture_command "ps aux" "$OUTPUT_DIR/processes.txt" "Running processes"

# Collect homelab service logs from /tmp
ok "Collecting homelab logs from /tmp..."
for log_file in /tmp/*.out /tmp/*.err; do
    if [[ -f "$log_file" ]]; then
        safe_copy "$log_file" "$OUTPUT_DIR/" "$(basename "$log_file")"
    fi
done

# Collect Docker/Colima logs
if command -v colima >/dev/null 2>&1; then
    capture_command "colima version" "$OUTPUT_DIR/colima_version.txt" "Colima version"
    capture_command "colima status" "$OUTPUT_DIR/colima_status.txt" "Colima status"
    capture_command "colima logs" "$OUTPUT_DIR/colima_logs.txt" "Colima logs"
fi

if command -v docker >/dev/null 2>&1; then
    capture_command "docker version" "$OUTPUT_DIR/docker_version.txt" "Docker version"
    capture_command "docker ps -a" "$OUTPUT_DIR/docker_containers.txt" "Docker containers"
    capture_command "docker images" "$OUTPUT_DIR/docker_images.txt" "Docker images"
    capture_command "docker system df" "$OUTPUT_DIR/docker_disk_usage.txt" "Docker disk usage"
fi

# Collect Immich logs
IMMICH_DIR="$(dirname "$0")/../services/immich"
if [[ -d "$IMMICH_DIR" ]]; then
    cd "$IMMICH_DIR"
    if [[ -f "docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
        capture_command "docker compose logs --tail=200" "$OUTPUT_DIR/immich_logs.txt" "Immich container logs"
    fi
    cd - >/dev/null
fi

# Collect Plex logs
PLEX_LOGS="$HOME/Library/Logs/Plex Media Server"
if [[ -d "$PLEX_LOGS" ]]; then
    mkdir -p "$OUTPUT_DIR/plex_logs"
    safe_copy "$PLEX_LOGS/Plex Media Server.log" "$OUTPUT_DIR/plex_logs/" "Plex main log"
    safe_copy "$PLEX_LOGS/Plex Media Scanner.log" "$OUTPUT_DIR/plex_logs/" "Plex scanner log"
    # Copy only recent crash logs
    find "$PLEX_LOGS" -name "*.crash" -mtime -7 -exec cp {} "$OUTPUT_DIR/plex_logs/" \; 2>/dev/null || true
fi

# Collect Tailscale status
if command -v tailscale >/dev/null 2>&1; then
    capture_command "tailscale version" "$OUTPUT_DIR/tailscale_version.txt" "Tailscale version"
    capture_command "tailscale status" "$OUTPUT_DIR/tailscale_status.txt" "Tailscale status"
    capture_command "tailscale serve status" "$OUTPUT_DIR/tailscale_serve.txt" "Tailscale serve status"
    capture_command "tailscale netcheck" "$OUTPUT_DIR/tailscale_netcheck.txt" "Tailscale network check"
fi

# Collect RAID status
if command -v diskutil >/dev/null 2>&1; then
    capture_command "diskutil list" "$OUTPUT_DIR/diskutil_list.txt" "Disk list"
    capture_command "diskutil appleRAID list" "$OUTPUT_DIR/raid_status.txt" "RAID status"
fi

# Collect LaunchD service status
capture_command "sudo launchctl list | grep homelab" "$OUTPUT_DIR/launchd_homelab.txt" "LaunchD homelab services"

# Collect Homebrew info
if command -v brew >/dev/null 2>&1; then
    capture_command "brew --version" "$OUTPUT_DIR/brew_version.txt" "Homebrew version"
    capture_command "brew services list" "$OUTPUT_DIR/brew_services.txt" "Homebrew services"
    capture_command "brew list --formula" "$OUTPUT_DIR/brew_packages.txt" "Installed packages"
fi

# Collect Caddy logs
if command -v caddy >/dev/null 2>&1; then
    capture_command "caddy version" "$OUTPUT_DIR/caddy_version.txt" "Caddy version"
    safe_copy "/opt/homebrew/var/log/caddy.log" "$OUTPUT_DIR/" "Caddy access log"
fi

# Collect system logs (recent errors)
capture_command "log show --predicate 'messageType == 16' --last 1h" "$OUTPUT_DIR/system_errors.txt" "Recent system errors"
capture_command "log show --predicate 'subsystem BEGINSWITH \"io.homelab\"' --last 24h" "$OUTPUT_DIR/homelab_system_logs.txt" "HomeHub system logs"

# Create compressed archive
ok "Creating compressed archive..."
cd /tmp
if tar -czf "$ARCHIVE_FILE" "homeserver-logs-$TIMESTAMP/" 2>/dev/null; then
    ok "Archive created: $ARCHIVE_FILE"
    
    # Get archive size
    archive_size=$(du -h "$ARCHIVE_FILE" | cut -f1)
    ok "Archive size: $archive_size"
    
    # Clean up temporary directory
    rm -rf "$OUTPUT_DIR"
    ok "Cleaned up temporary files"
    
    echo -e "\n${GREEN}✅ Log collection complete!${NC}"
    echo "Archive: $ARCHIVE_FILE"
    echo ""
    echo "💡 Usage:"
    echo "   - Review logs: tar -tzf $ARCHIVE_FILE"
    echo "   - Extract: tar -xzf $ARCHIVE_FILE"
    echo "   - Send for support: Upload the .tgz file"
    
else
    fail "Failed to create archive"
    warn "Logs available in: $OUTPUT_DIR"
fi

print_summary