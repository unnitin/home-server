#!/usr/bin/env bash
# scripts/migration/lib/migration_common.sh
# Shared migration utilities and common functions

# Prevent multiple sourcing
[[ "${MIGRATION_COMMON_LOADED:-}" == "1" ]] && return 0
export MIGRATION_COMMON_LOADED=1

# Migration logging with timestamps
migration_log() {
    local level="$1"
    shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
}

log_info() { migration_log "INFO" "$@"; }
log_warn() { migration_log "WARN" "$@"; }
log_error() { migration_log "ERROR" "$@"; }
log_success() { migration_log "SUCCESS" "$@"; }

# Safety checks for migration operations
require_safety_acknowledgment() {
    if [[ "${MIGRATION_I_UNDERSTAND_DATA_RISK:-0}" != "1" ]]; then
        log_error "Set MIGRATION_I_UNDERSTAND_DATA_RISK=1 to acknowledge migration risks"
        exit 2
    fi
}

# Validate storage tier exists
validate_storage_tier() {
    local tier="$1"
    local mount_point="/Volumes/$tier"
    
    if [[ ! -d "$mount_point" ]]; then
        log_error "Storage tier '$tier' not found at $mount_point"
        return 1
    fi
    
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_warn "Storage tier '$tier' exists but may not be properly mounted"
    fi
    
    log_info "Storage tier '$tier' validated"
    return 0
}

# Get available space for a storage tier
get_tier_space() {
    local tier="$1"
    local mount_point="/Volumes/$tier"
    
    if [[ -d "$mount_point" ]]; then
        df -h "$mount_point" | awk 'NR==2 {print $4}'
    else
        echo "N/A"
    fi
}

# Check if a service is running
is_service_running() {
    local service="$1"
    
    case "$service" in
        "plex")
            pgrep -f "Plex Media Server" >/dev/null 2>&1
            ;;
        "immich")
            docker ps --format "table {{.Names}}" | grep -q "immich-server" 2>/dev/null
            ;;
        "docker")
            docker ps >/dev/null 2>&1
            ;;
        "colima")
            colima status >/dev/null 2>&1
            ;;
        *)
            log_warn "Unknown service: $service"
            return 1
            ;;
    esac
}

# Stop a service gracefully
stop_service() {
    local service="$1"
    
    log_info "Stopping service: $service"
    
    case "$service" in
        "plex")
            pkill -f "Plex Media Server" || true
            launchctl unload ~/Library/LaunchAgents/io.homelab.plex.plist 2>/dev/null || true
            ;;
        "immich")
            if [[ -f "services/immich/docker-compose.yml" ]]; then
                (cd services/immich && docker compose down) || true
            fi
            ;;
        "colima")
            colima stop 2>/dev/null || true
            ;;
        *)
            log_warn "Don't know how to stop service: $service"
            return 1
            ;;
    esac
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    if is_service_running "$service"; then
        log_warn "Service $service may still be running"
        return 1
    else
        log_success "Service $service stopped"
        return 0
    fi
}

# Start a service
start_service() {
    local service="$1"
    
    log_info "Starting service: $service"
    
    case "$service" in
        "plex")
            launchctl load ~/Library/LaunchAgents/io.homelab.plex.plist 2>/dev/null || true
            ;;
        "immich")
            if [[ -f "services/immich/docker-compose.yml" ]]; then
                (cd services/immich && docker compose up -d) || true
            fi
            ;;
        "colima")
            colima start || true
            ;;
        *)
            log_warn "Don't know how to start service: $service"
            return 1
            ;;
    esac
    
    log_success "Service $service start command issued"
    return 0
}

# Create a timestamped backup directory
create_backup_dir() {
    local base_dir="$1"
    local migration_type="$2"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$base_dir/migration_backup_${migration_type}_$timestamp"
    
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Validate data integrity using checksums
validate_data_integrity() {
    local source="$1"
    local target="$2"
    
    log_info "Validating data integrity between $source and $target"
    
    if [[ ! -d "$source" ]] || [[ ! -d "$target" ]]; then
        log_error "Source or target directory does not exist"
        return 1
    fi
    
    # Use diff for quick comparison (works for most cases)
    if diff -r "$source" "$target" >/dev/null 2>&1; then
        log_success "Data integrity validation passed"
        return 0
    else
        log_error "Data integrity validation failed"
        return 1
    fi
}

# Create or update a symlink safely
create_symlink() {
    local target="$1"
    local link_path="$2"
    
    log_info "Creating symlink: $link_path -> $target"
    
    # Remove existing symlink or file
    if [[ -L "$link_path" ]]; then
        rm "$link_path"
        log_info "Removed existing symlink"
    elif [[ -e "$link_path" ]]; then
        log_error "Path $link_path exists but is not a symlink"
        return 1
    fi
    
    # Create parent directory if needed
    local parent_dir=$(dirname "$link_path")
    mkdir -p "$parent_dir"
    
    # Create the symlink
    ln -sf "$target" "$link_path"
    
    # Verify the symlink
    if [[ -L "$link_path" ]] && [[ "$(readlink "$link_path")" == "$target" ]]; then
        log_success "Symlink created successfully"
        return 0
    else
        log_error "Failed to create symlink"
        return 1
    fi
}

# Get data types from a comma-separated string
parse_data_types() {
    local data_types_string="$1"
    echo "$data_types_string" | tr ',' '\n'
}

# Check if a data type is supported
is_supported_data_type() {
    local data_type="$1"
    
    case "$data_type" in
        "photos"|"plex-metadata"|"docker-volumes"|"processing-dirs"|"immich-processing"|"plex-processing")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Get the source path for a data type
get_data_type_source() {
    local data_type="$1"
    local source_tier="$2"
    
    case "$data_type" in
        "photos")
            echo "/Volumes/${source_tier}/Photos"
            ;;
        "plex-metadata")
            echo "~/Library/Application Support/Plex Media Server"
            ;;
        "docker-volumes")
            echo "docker-volumes"  # Special case
            ;;
        "processing-dirs")
            echo "processing-dirs"  # Special case
            ;;
        "immich-processing")
            echo "/Volumes/${source_tier}/immich_processing"
            ;;
        "plex-processing")
            echo "/Volumes/${source_tier}/plex_processing"
            ;;
        *)
            log_error "Unknown data type: $data_type"
            return 1
            ;;
    esac
}

# Get the target path for a data type
get_data_type_target() {
    local data_type="$1"
    local target_tier="$2"
    
    case "$data_type" in
        "photos")
            echo "/Volumes/${target_tier}/photos"
            ;;
        "plex-metadata")
            echo "/Volumes/${target_tier}/plex_metadata"
            ;;
        "docker-volumes")
            echo "/Volumes/${target_tier}/docker_data"
            ;;
        "processing-dirs")
            echo "/Volumes/${target_tier}"  # Base directory
            ;;
        "immich-processing")
            echo "/Volumes/${target_tier}/immich_processing"
            ;;
        "plex-processing")
            echo "/Volumes/${target_tier}/plex_processing"
            ;;
        *)
            log_error "Unknown data type: $data_type"
            return 1
            ;;
    esac
}

# Export functions for use by other scripts
export -f migration_log log_info log_warn log_error log_success
export -f require_safety_acknowledgment validate_storage_tier get_tier_space
export -f is_service_running stop_service start_service
export -f create_backup_dir validate_data_integrity create_symlink
export -f parse_data_types is_supported_data_type
export -f get_data_type_source get_data_type_target
