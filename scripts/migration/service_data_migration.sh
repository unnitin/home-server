#!/usr/bin/env bash
# scripts/migration/service_data_migration.sh
# Handles service-specific data migration (Plex metadata, Docker volumes, etc.)

set -euo pipefail

# Source migration libraries
source "$(dirname "$0")/lib/migration_common.sh"

# Default values
SERVICE=""
TARGET_TIER=""
TARGET_LOCATION=""

# Usage information
usage() {
    cat << 'EOF'
🔄 Service Data Migration

USAGE:
    ./scripts/migration/service_data_migration.sh [OPTIONS]

REQUIRED:
    --service <service>     Service to migrate (plex, docker, immich)
    --target-tier <tier>    Target storage tier (warmstore, faststore, coldstore)

OR:
    --service <service>     Service to migrate
    --target-location <path> Custom target location

OPTIONS:
    --help                  Show this help

SERVICES:
    plex                    Plex Media Server metadata and preferences
    docker                  Docker volumes and container data
    immich                  Immich application data (database, cache)

EXAMPLES:
    # Migrate Plex metadata to faststore
    ./scripts/migration/service_data_migration.sh \
        --service plex \
        --target-tier faststore

    # Migrate Docker data to faststore
    ./scripts/migration/service_data_migration.sh \
        --service docker \
        --target-tier faststore

    # Migrate to custom location
    ./scripts/migration/service_data_migration.sh \
        --service plex \
        --target-location /Volumes/faststore/custom_plex

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --target-tier)
            TARGET_TIER="$2"
            shift 2
            ;;
        --target-location)
            TARGET_LOCATION="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validation
validate_arguments() {
    local errors=0
    
    if [[ -z "$SERVICE" ]]; then
        log_error "Missing required argument: --service"
        ((errors++))
    fi
    
    if [[ -z "$TARGET_TIER" && -z "$TARGET_LOCATION" ]]; then
        log_error "Must specify either --target-tier or --target-location"
        ((errors++))
    fi
    
    if [[ -n "$TARGET_TIER" && -n "$TARGET_LOCATION" ]]; then
        log_error "Cannot specify both --target-tier and --target-location"
        ((errors++))
    fi
    
    case "$SERVICE" in
        "plex"|"docker"|"immich")
            # Valid services
            ;;
        *)
            log_error "Unsupported service: $SERVICE"
            ((errors++))
            ;;
    esac
    
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        exit 1
    fi
}

# Get target location for service
get_service_target_location() {
    if [[ -n "$TARGET_LOCATION" ]]; then
        echo "$TARGET_LOCATION"
        return 0
    fi
    
    case "$SERVICE" in
        "plex")
            echo "/Volumes/$TARGET_TIER/plex_metadata"
            ;;
        "docker")
            echo "/Volumes/$TARGET_TIER/docker_data"
            ;;
        "immich")
            echo "/Volumes/$TARGET_TIER/immich_data"
            ;;
        *)
            log_error "Unknown service: $SERVICE"
            return 1
            ;;
    esac
}

# Migrate Plex metadata
migrate_plex() {
    local target_location="$1"
    local source_location="$HOME/Library/Application Support/Plex Media Server"
    
    log_info "Migrating Plex metadata to $target_location"
    
    # Stop Plex
    stop_service "plex"
    
    # Create target directory
    sudo mkdir -p "$target_location"
    sudo chown $(whoami):staff "$target_location"
    
    # Migrate metadata if it exists
    if [[ -d "$source_location" ]]; then
        log_info "Copying Plex metadata..."
        rsync -av --progress "$source_location/" "$target_location/"
        
        # Verify copy
        if [[ "$?" -eq 0 ]]; then
            log_info "Creating symlink..."
            rm -rf "$source_location"
            create_symlink "$target_location" "$source_location"
        else
            log_error "Failed to copy Plex metadata"
            return 1
        fi
    else
        log_info "No existing Plex metadata found, creating empty structure"
        create_symlink "$target_location" "$source_location"
    fi
    
    # Start Plex
    start_service "plex"
    
    log_success "Plex metadata migration completed"
}

# Migrate Docker data
migrate_docker() {
    local target_location="$1"
    
    log_info "Migrating Docker data to $target_location"
    
    # Stop Docker services
    stop_service "immich"
    stop_service "colima"
    
    # Create target directory
    sudo mkdir -p "$target_location"
    sudo chown $(whoami):staff "$target_location"
    
    # Backup existing Immich database if it exists
    if docker volume ls 2>/dev/null | grep -q immich-db; then
        log_info "Backing up Immich database..."
        docker run --rm \
            -v immich-db:/data \
            -v "$target_location":/backup \
            alpine tar czf /backup/immich-db-backup-$(date +%Y%m%d_%H%M%S).tar.gz -C /data . || true
        
        # Remove old volume
        docker volume rm immich-db || true
    fi
    
    # Configure Colima for new storage location
    log_info "Configuring Colima for new storage location..."
    mkdir -p ~/.colima/default/
    
    cat > ~/.colima/default/colima.yaml << EOF
# Colima configuration for storage tier: $TARGET_TIER
cpu: 4
memory: 8
disk: 100

# Mount target storage for Docker data
mount:
  - location: $target_location
    writable: true
EOF
    
    # Create Immich database directory
    mkdir -p "$target_location/immich-db"
    
    # Update Immich docker-compose.yml if it exists
    local compose_file="services/immich/docker-compose.yml"
    if [[ -f "$compose_file" ]]; then
        log_info "Updating Immich configuration..."
        
        # Backup original
        cp "$compose_file" "$compose_file.backup"
        
        # Check if volumes section needs updating
        if ! grep -q "device: $target_location/immich-db" "$compose_file"; then
            cat >> "$compose_file" << EOF

# Storage tier configuration - managed by migration
volumes:
  immich-db:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: $target_location/immich-db
EOF
        fi
    fi
    
    # Start services
    start_service "colima"
    start_service "immich"
    
    log_success "Docker data migration completed"
}

# Migrate Immich data
migrate_immich() {
    local target_location="$1"
    
    log_info "Migrating Immich data to $target_location"
    
    # This is primarily handled by Docker migration
    # But we can create Immich-specific structure
    
    sudo mkdir -p "$target_location"/{database,uploads,cache}
    sudo chown $(whoami):staff "$target_location"/{database,uploads,cache}
    
    log_success "Immich data migration completed"
}

# Main migration logic
migrate_service() {
    local target_location=$(get_service_target_location)
    
    log_info "Starting migration of $SERVICE to $target_location"
    
    case "$SERVICE" in
        "plex")
            migrate_plex "$target_location"
            ;;
        "docker")
            migrate_docker "$target_location"
            ;;
        "immich")
            migrate_immich "$target_location"
            ;;
        *)
            log_error "Migration not implemented for service: $SERVICE"
            return 1
            ;;
    esac
}

# Main execution
main() {
    echo "🔄 Service Data Migration"
    echo "========================"
    
    validate_arguments
    
    # Validate target tier if specified
    if [[ -n "$TARGET_TIER" ]]; then
        validate_storage_tier "$TARGET_TIER"
    fi
    
    migrate_service
    
    log_success "Service data migration completed successfully!"
}

# Execute main function
main "$@"
