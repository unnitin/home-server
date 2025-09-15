#!/usr/bin/env bash
# scripts/migration/storage_tier_migration.sh
# Handles migration between storage tiers with data type awareness

set -euo pipefail

# Source migration libraries
source "$(dirname "$0")/lib/migration_common.sh"

# Default values
SOURCE_TIER=""
TARGET_TIER=""
DATA_TYPE=""
VERIFY_INTEGRITY=true

# Usage information
usage() {
    cat << 'EOF'
🔄 Storage Tier Migration

USAGE:
    ./scripts/migration/storage_tier_migration.sh [OPTIONS]

REQUIRED:
    --source-tier <tier>    Source storage tier (warmstore, faststore, coldstore)
    --target-tier <tier>    Target storage tier (warmstore, faststore, coldstore)
    --data-type <type>      Data type to migrate

DATA TYPES:
    photos                  Photo storage (Immich)
    processing-dirs         Service processing directories
    immich-processing       Immich temp processing
    plex-processing         Plex transcoding cache

OPTIONS:
    --no-verify            Skip data integrity verification
    --help                 Show this help

EXAMPLES:
    # Migrate photos from warmstore to faststore
    ./scripts/migration/storage_tier_migration.sh \
        --source-tier warmstore \
        --target-tier faststore \
        --data-type photos

    # Migrate processing directories
    ./scripts/migration/storage_tier_migration.sh \
        --source-tier warmstore \
        --target-tier faststore \
        --data-type processing-dirs

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-tier)
            SOURCE_TIER="$2"
            shift 2
            ;;
        --target-tier)
            TARGET_TIER="$2"
            shift 2
            ;;
        --data-type)
            DATA_TYPE="$2"
            shift 2
            ;;
        --no-verify)
            VERIFY_INTEGRITY=false
            shift
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
    
    if [[ -z "$SOURCE_TIER" ]]; then
        log_error "Missing required argument: --source-tier"
        ((errors++))
    fi
    
    if [[ -z "$TARGET_TIER" ]]; then
        log_error "Missing required argument: --target-tier"
        ((errors++))
    fi
    
    if [[ -z "$DATA_TYPE" ]]; then
        log_error "Missing required argument: --data-type"
        ((errors++))
    fi
    
    if [[ "$SOURCE_TIER" == "$TARGET_TIER" ]]; then
        log_error "Source and target tiers cannot be the same"
        ((errors++))
    fi
    
    if ! is_supported_data_type "$DATA_TYPE"; then
        log_error "Unsupported data type: $DATA_TYPE"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        exit 1
    fi
}

# Migrate photos data type
migrate_photos() {
    local source_path=$(get_data_type_source "$DATA_TYPE" "$SOURCE_TIER")
    local target_path=$(get_data_type_target "$DATA_TYPE" "$TARGET_TIER")
    
    log_info "Migrating photos from $source_path to $target_path"
    
    # Expand tilde in source path if present
    source_path="${source_path/#\~/$HOME}"
    
    # Stop Immich during photo migration
    stop_service "immich"
    
    # Create target directory structure
    sudo mkdir -p "$target_path"
    sudo chown $(whoami):staff "$target_path"
    
    # Migrate data if source exists and has content
    if [[ -d "$source_path" && "$(ls -A "$source_path" 2>/dev/null || true)" ]]; then
        log_info "Copying photo data..."
        rsync -av --progress "$source_path/" "$target_path/"
        
        # Verify integrity if requested
        if [[ "$VERIFY_INTEGRITY" == "true" ]]; then
            validate_data_integrity "$source_path" "$target_path"
        fi
    else
        log_info "No existing photo data found, creating empty structure"
    fi
    
    # Update Photos symlink
    create_symlink "$target_path" "/Volumes/Photos"
    
    # Restart Immich
    start_service "immich"
    
    log_success "Photos migration completed"
}

# Migrate processing directories
migrate_processing_dirs() {
    log_info "Creating processing directories on $TARGET_TIER"
    
    case "$DATA_TYPE" in
        "processing-dirs")
            # Create both processing directories
            sudo mkdir -p "/Volumes/$TARGET_TIER"/{plex_processing,immich_processing}
            sudo chown $(whoami):staff "/Volumes/$TARGET_TIER"/{plex_processing,immich_processing}
            chmod 755 "/Volumes/$TARGET_TIER"/{plex_processing,immich_processing}
            
            # Create service access symlinks
            create_symlink "/Volumes/$TARGET_TIER/plex_processing" "/Volumes/Media/plex_processing"
            create_symlink "/Volumes/$TARGET_TIER/immich_processing" "/Volumes/Photos/immich_processing"
            ;;
        "plex-processing")
            sudo mkdir -p "/Volumes/$TARGET_TIER/plex_processing"
            sudo chown $(whoami):staff "/Volumes/$TARGET_TIER/plex_processing"
            chmod 755 "/Volumes/$TARGET_TIER/plex_processing"
            create_symlink "/Volumes/$TARGET_TIER/plex_processing" "/Volumes/Media/plex_processing"
            ;;
        "immich-processing")
            sudo mkdir -p "/Volumes/$TARGET_TIER/immich_processing"
            sudo chown $(whoami):staff "/Volumes/$TARGET_TIER/immich_processing"
            chmod 755 "/Volumes/$TARGET_TIER/immich_processing"
            create_symlink "/Volumes/$TARGET_TIER/immich_processing" "/Volumes/Photos/immich_processing"
            ;;
        *)
            log_error "Unknown processing directory type: $DATA_TYPE"
            return 1
            ;;
    esac
    
    log_success "Processing directories migration completed"
}

# Main migration logic
migrate_data_type() {
    log_info "Starting migration of $DATA_TYPE from $SOURCE_TIER to $TARGET_TIER"
    
    case "$DATA_TYPE" in
        "photos")
            migrate_photos
            ;;
        "processing-dirs"|"plex-processing"|"immich-processing")
            migrate_processing_dirs
            ;;
        *)
            log_error "Migration not implemented for data type: $DATA_TYPE"
            return 1
            ;;
    esac
}

# Main execution
main() {
    echo "🔄 Storage Tier Migration"
    echo "========================"
    
    validate_arguments
    
    # Validate storage tiers exist
    validate_storage_tier "$SOURCE_TIER"
    validate_storage_tier "$TARGET_TIER"
    
    migrate_data_type
    
    log_success "Storage tier migration completed successfully!"
}

# Execute main function
main "$@"
