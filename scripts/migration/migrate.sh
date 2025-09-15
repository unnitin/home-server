#!/usr/bin/env bash
# scripts/migration/migrate.sh
# Main migration orchestrator with comprehensive capabilities

set -euo pipefail

# Source migration libraries
source "$(dirname "$0")/lib/migration_common.sh"

# Default values
DRY_RUN=false
PHASE="full"
BACKUP_DIR=""
FROM_TIER=""
TO_TIER=""
DATA_TYPES=""
FORCE=false

# Usage information
usage() {
    cat << 'EOF'
🔄 Migration Orchestrator

USAGE:
    ./scripts/migration/migrate.sh --from <source> --to <target> [OPTIONS]

REQUIRED:
    --from <tier>           Source storage tier (warmstore, faststore, coldstore)
    --to <tier>             Target storage tier (warmstore, faststore, coldstore)  
    --data-types <types>    Comma-separated data types to migrate

DATA TYPES:
    photos                  Photo storage (Immich)
    plex-metadata          Plex Media Server metadata
    docker-volumes         Docker container volumes
    processing-dirs        Service processing directories
    immich-processing      Immich temp processing
    plex-processing        Plex transcoding cache

OPTIONS:
    --phase <phase>         Migration phase: quick-wins, advanced, full (default: full)
    --dry-run              Show what would be done without making changes
    --backup-dir <dir>     Custom backup directory (default: auto-generated)
    --force                Skip interactive confirmations
    --help                 Show this help

PHASES:
    quick-wins             Low-risk: processing directories, cache
    advanced               Medium-risk: metadata, docker volumes  
    full                   All phases: complete migration

EXAMPLES:
    # Complete faststore migration
    ./scripts/migration/migrate.sh \
        --from warmstore \
        --to faststore \
        --data-types "photos,plex-metadata,docker-volumes"

    # Phase 1 only (quick wins)
    ./scripts/migration/migrate.sh \
        --from warmstore \
        --to faststore \
        --phase quick-wins \
        --data-types "processing-dirs"

    # Dry run to see what would happen
    ./scripts/migration/migrate.sh \
        --from warmstore \
        --to faststore \
        --data-types "photos" \
        --dry-run

SAFETY:
    Set MIGRATION_I_UNDERSTAND_DATA_RISK=1 before running (required)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --from)
            FROM_TIER="$2"
            shift 2
            ;;
        --to)
            TO_TIER="$2"
            shift 2
            ;;
        --data-types)
            DATA_TYPES="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --backup-dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
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
    
    if [[ -z "$FROM_TIER" ]]; then
        log_error "Missing required argument: --from"
        ((errors++))
    fi
    
    if [[ -z "$TO_TIER" ]]; then
        log_error "Missing required argument: --to"
        ((errors++))
    fi
    
    if [[ -z "$DATA_TYPES" ]]; then
        log_error "Missing required argument: --data-types"
        ((errors++))
    fi
    
    if [[ "$FROM_TIER" == "$TO_TIER" ]]; then
        log_error "Source and target tiers cannot be the same"
        ((errors++))
    fi
    
    if [[ "$PHASE" != "quick-wins" && "$PHASE" != "advanced" && "$PHASE" != "full" ]]; then
        log_error "Invalid phase: $PHASE (must be: quick-wins, advanced, full)"
        ((errors++))
    fi
    
    # Validate data types
    for data_type in $(parse_data_types "$DATA_TYPES"); do
        if ! is_supported_data_type "$data_type"; then
            log_error "Unsupported data type: $data_type"
            ((errors++))
        fi
    done
    
    if [[ $errors -gt 0 ]]; then
        log_error "Validation failed with $errors error(s)"
        usage
        exit 1
    fi
}

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    
    # Safety acknowledgment
    if [[ "$DRY_RUN" == "false" ]]; then
        require_safety_acknowledgment
    fi
    
    # Validate storage tiers
    validate_storage_tier "$FROM_TIER"
    validate_storage_tier "$TO_TIER"
    
    # Check available space
    local from_space=$(get_tier_space "$FROM_TIER")
    local to_space=$(get_tier_space "$TO_TIER")
    
    log_info "Storage space - From: $from_space, To: $to_space"
    
    # Check if target tier has sufficient space (simplified check)
    # In a real implementation, you'd calculate actual data size
    
    log_success "Pre-flight checks completed"
}

# Interactive confirmation
confirm_migration() {
    if [[ "$FORCE" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    echo
    log_info "Migration Summary:"
    echo "  From: $FROM_TIER"
    echo "  To: $TO_TIER"
    echo "  Data Types: $DATA_TYPES"
    echo "  Phase: $PHASE"
    echo "  Backup Dir: ${BACKUP_DIR:-auto-generated}"
    echo
    
    read -p "Proceed with migration? [y/N]: " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled by user"
        exit 0
    fi
}

# Create backup
create_migration_backup() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup directory"
        return 0
    fi
    
    # Create backup directory if not specified
    if [[ -z "$BACKUP_DIR" ]]; then
        BACKUP_DIR=$(create_backup_dir "/Volumes/$FROM_TIER" "${FROM_TIER}_to_${TO_TIER}")
    else
        mkdir -p "$BACKUP_DIR"
    fi
    
    log_info "Creating migration backup at: $BACKUP_DIR"
    
    # Call backup script for each data type
    for data_type in $(parse_data_types "$DATA_TYPES"); do
        log_info "Backing up data type: $data_type"
        ./scripts/migration/backup.sh \
            --data-type "$data_type" \
            --source-tier "$FROM_TIER" \
            --backup-dir "$BACKUP_DIR"
    done
    
    # Document current state
    diskutil list > "$BACKUP_DIR/diskutil_before.txt"
    mount > "$BACKUP_DIR/mounts_before.txt"
    docker volume ls > "$BACKUP_DIR/docker_volumes_before.txt" 2>/dev/null || true
    
    log_success "Backup completed"
}

# Execute migration based on phase
execute_migration() {
    log_info "Executing migration phase: $PHASE"
    
    case "$PHASE" in
        "quick-wins")
            execute_quick_wins
            ;;
        "advanced")
            execute_advanced
            ;;
        "full")
            execute_quick_wins
            execute_advanced
            ;;
        *)
            log_error "Unknown phase: $PHASE"
            exit 1
            ;;
    esac
}

# Quick wins phase
execute_quick_wins() {
    log_info "Phase 1: Quick Wins"
    
    for data_type in $(parse_data_types "$DATA_TYPES"); do
        case "$data_type" in
            "processing-dirs"|"immich-processing"|"plex-processing")
                migrate_processing_directories "$data_type"
                ;;
        esac
    done
}

# Advanced phase
execute_advanced() {
    log_info "Phase 2: Advanced Optimizations"
    
    for data_type in $(parse_data_types "$DATA_TYPES"); do
        case "$data_type" in
            "photos"|"plex-metadata"|"docker-volumes")
                migrate_data_type "$data_type"
                ;;
        esac
    done
}

# Migrate processing directories
migrate_processing_directories() {
    local data_type="$1"
    
    log_info "Migrating processing directories: $data_type"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would migrate $data_type processing directories"
        return 0
    fi
    
    ./scripts/migration/storage_tier_migration.sh \
        --source-tier "$FROM_TIER" \
        --target-tier "$TO_TIER" \
        --data-type "$data_type"
}

# Migrate a specific data type
migrate_data_type() {
    local data_type="$1"
    
    log_info "Migrating data type: $data_type"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would migrate $data_type"
        return 0
    fi
    
    # Use appropriate migration script based on data type
    case "$data_type" in
        "photos")
            ./scripts/migration/storage_tier_migration.sh \
                --source-tier "$FROM_TIER" \
                --target-tier "$TO_TIER" \
                --data-type "$data_type"
            ;;
        "plex-metadata")
            ./scripts/migration/service_data_migration.sh \
                --service plex \
                --target-tier "$TO_TIER"
            ;;
        "docker-volumes")
            ./scripts/migration/service_data_migration.sh \
                --service docker \
                --target-tier "$TO_TIER"
            ;;
        *)
            log_warn "Unknown data type for advanced migration: $data_type"
            ;;
    esac
}

# Post-migration validation
post_migration_validation() {
    log_info "Running post-migration validation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run validation"
        return 0
    fi
    
    ./scripts/migration/validate.sh \
        --migration "storage-tier" \
        --from "$FROM_TIER" \
        --to "$TO_TIER" \
        --data-types "$DATA_TYPES"
}

# Main execution
main() {
    echo "🔄 Migration Orchestrator"
    echo "========================"
    
    validate_arguments
    preflight_checks
    confirm_migration
    
    if [[ "$DRY_RUN" == "false" ]]; then
        create_migration_backup
    fi
    
    execute_migration
    post_migration_validation
    
    echo
    log_success "Migration completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "Backup location: $BACKUP_DIR"
        echo "Run './scripts/migration/validate.sh --migration storage-tier' for detailed validation"
    fi
}

# Execute main function
main "$@"
