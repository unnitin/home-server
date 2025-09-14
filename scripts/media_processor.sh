#!/usr/bin/env bash
set -euo pipefail

# Media Processor - Main orchestrator for Plex media processing
# Processes files from Staging directories and organizes them according to Plex naming conventions

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
WARMSTORE="/Volumes/warmstore"
STAGING_DIR="$WARMSTORE/Staging"
MOVIES_STAGING="$STAGING_DIR/Movies"
TV_STAGING="$STAGING_DIR/TV Shows"
COLLECTIONS_STAGING="$STAGING_DIR/Collections"
LOGS_DIR="$WARMSTORE/logs/media-watcher"

MOVIES_TARGET="$WARMSTORE/Movies"
TV_TARGET="$WARMSTORE/TV Shows"
COLLECTIONS_TARGET="$WARMSTORE/Collections"

# Logging setup (directory created later if needed)
LOG_FILE="$LOGS_DIR/media_processor_$(date +%Y%m%d_%H%M%S).log"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Graceful failure handling
fail_gracefully() {
    local operation="$1"
    local file="$2"
    local error="$3"
    
    log_error "Failed $operation for '$file': $error"
    
    # Move problematic file to failed directory
    local failed_dir="$STAGING_DIR/failed/$(date +%Y%m%d)"
    mkdir -p "$failed_dir"
    
    if [[ -f "$file" ]]; then
        local basename=$(basename "$file")
        mv "$file" "$failed_dir/$basename" 2>/dev/null || true
        log_warn "Moved problematic file to: $failed_dir/$basename"
    fi
    
    return 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Staging directories exist
    for dir in "$STAGING_DIR" "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING" "$LOGS_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_info "Created directory: $dir"
        fi
    done
    
    # Check if target directories exist
    for dir in "$MOVIES_TARGET" "$TV_TARGET" "$COLLECTIONS_TARGET"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Target directory does not exist: $dir"
            return 1
        fi
    done
    
    # Check for required tools
    for tool in ffprobe mediainfo; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_warn "$tool not found - some features may be limited"
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Process movies (with recursive directory support)
process_movies() {
    log_info "Processing movies from Staging..."
    
    if [[ ! -d "$MOVIES_STAGING" ]] || [[ -z "$(find "$MOVIES_STAGING" -type f 2>/dev/null)" ]]; then
        log_info "No movies found in Staging directory"
        return 0
    fi
    
    local processed=0
    local failed=0
    
    # Process all media files recursively, preserving directory structure
    find "$MOVIES_STAGING" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" -o -name "*.wmv" -o -name "*.flv" -o -name "*.webm" \) | while read -r movie_file; do
        log_info "Processing movie: $(basename "$movie_file")"
        
        # Calculate relative path from staging directory
        local rel_path="${movie_file#$MOVIES_STAGING/}"
        local rel_dir="$(dirname "$rel_path")"
        
        # Determine target directory (preserve subfolder structure)
        local target_dir="$MOVIES_TARGET"
        if [[ "$rel_dir" != "." ]]; then
            target_dir="$MOVIES_TARGET/$rel_dir"
        fi
        
        if "$SCRIPT_DIR/process_movie.sh" "$movie_file" "$target_dir" "$LOG_FILE" "$rel_path"; then
            ((processed++))
            log_success "Successfully processed: $rel_path"
        else
            ((failed++))
            fail_gracefully "movie processing" "$movie_file" "See process_movie.sh logs"
        fi
    done
    
    log_info "Movies processing complete: $processed processed, $failed failed"
}

# Process TV shows (with recursive directory support)
process_tv_shows() {
    log_info "Processing TV shows from Staging..."
    
    if [[ ! -d "$TV_STAGING" ]] || [[ -z "$(find "$TV_STAGING" -type f 2>/dev/null)" ]]; then
        log_info "No TV shows found in Staging directory"
        return 0
    fi
    
    local processed=0
    local failed=0
    
    # Process all media files recursively, preserving directory structure
    find "$TV_STAGING" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" -o -name "*.wmv" -o -name "*.flv" -o -name "*.webm" \) | while read -r tv_file; do
        log_info "Processing TV episode: $(basename "$tv_file")"
        
        # Calculate relative path from staging directory
        local rel_path="${tv_file#$TV_STAGING/}"
        local rel_dir="$(dirname "$rel_path")"
        
        if "$SCRIPT_DIR/process_tv_show.sh" "$tv_file" "$TV_TARGET" "$LOG_FILE" "$rel_path"; then
            ((processed++))
            log_success "Successfully processed: $rel_path"
        else
            ((failed++))
            fail_gracefully "TV show processing" "$tv_file" "See process_tv_show.sh logs"
        fi
    done
    
    log_info "TV shows processing complete: $processed processed, $failed failed"
}

# Process Collections (preserves exact folder structure)
process_collections() {
    log_info "Processing Collections from Staging..."
    
    if [[ ! -d "$COLLECTIONS_STAGING" ]] || [[ -z "$(find "$COLLECTIONS_STAGING" -type f 2>/dev/null)" ]]; then
        log_info "No Collections found in Staging directory"
        return 0
    fi
    
    local processed=0
    local failed=0
    
    # Process all media files recursively, preserving exact directory structure
    find "$COLLECTIONS_STAGING" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" -o -name "*.wmv" -o -name "*.flv" -o -name "*.webm" \) | while read -r collection_file; do
        log_info "Processing Collection item: $(basename "$collection_file")"
        
        # Calculate relative path from staging directory
        local rel_path="${collection_file#$COLLECTIONS_STAGING/}"
        local rel_dir="$(dirname "$rel_path")"
        
        # Determine target directory (preserve exact subfolder structure)
        local target_dir="$COLLECTIONS_TARGET"
        if [[ "$rel_dir" != "." ]]; then
            target_dir="$COLLECTIONS_TARGET/$rel_dir"
        fi
        
        if "$SCRIPT_DIR/process_collection.sh" "$collection_file" "$target_dir" "$LOG_FILE" "$rel_path"; then
            ((processed++))
            log_success "Successfully processed: $rel_path"
        else
            ((failed++))
            fail_gracefully "collection processing" "$collection_file" "See process_collection.sh logs"
        fi
    done
    
    log_info "Collections processing complete: $processed processed, $failed failed"
}

# Clean up staging area after processing
cleanup_staging() {
    log_info "Cleaning up Staging directories..."
    
    # Remove any remaining media files that might have been left behind
    local cleanup_count=0
    
    # Clean up any leftover media files in staging (these would be files that failed to process)
    for staging_area in "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING"; do
        if [[ -d "$staging_area" ]]; then
            # Find and log any remaining media files
            while IFS= read -r -d '' leftover_file; do
                log_warn "Leftover file found: $(basename "$leftover_file")"
                # Move to failed directory for investigation
                local failed_dir="$STAGING_DIR/failed/$(date +%Y%m%d)"
                mkdir -p "$failed_dir"
                if mv "$leftover_file" "$failed_dir/"; then
                    log_info "Moved leftover file to failed directory: $(basename "$leftover_file")"
                    ((cleanup_count++))
                fi
            done < <(find "$staging_area" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" -o -name "*.wmv" -o -name "*.flv" -o -name "*.webm" \) -print0 2>/dev/null)
        fi
    done
    
    # Remove empty directories in staging, but preserve the main staging structure
    # Only remove subdirectories that are empty, not the main staging folders
    for staging_area in "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING"; do
        if [[ -d "$staging_area" ]]; then
            # Remove empty subdirectories within each staging area
            find "$staging_area" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        fi
    done
    
    # Clean up system files and metadata (but preserve directory structure)
    local system_files_cleaned=0
    for staging_area in "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING"; do
        if [[ -d "$staging_area" ]]; then
            # Remove common system/metadata files
            while IFS= read -r -d '' system_file; do
                if rm "$system_file" 2>/dev/null; then
                    ((system_files_cleaned++))
                fi
            done < <(find "$staging_area" -type f \( -name ".DS_Store" -o -name "Thumbs.db" -o -name "desktop.ini" -o -name "._.DS_Store" -o -name "._*" \) -print0 2>/dev/null)
        fi
    done
    
    if [[ $system_files_cleaned -gt 0 ]]; then
        log_info "Cleaned up $system_files_cleaned system/metadata files"
    fi
    
    # Ensure main staging directories always exist for future use
    mkdir -p "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING" "$LOGS_DIR"
    
    # Clean up old log files (keep last 30 days)
    find "$LOGS_DIR" -name "media_processor_*.log" -mtime +30 -delete 2>/dev/null || true
    
    # Clean up old failed files (keep last 7 days)
    find "$STAGING_DIR/failed" -type f -mtime +7 -delete 2>/dev/null || true
    find "$STAGING_DIR/failed" -type d -empty -delete 2>/dev/null || true
    
    if [[ $cleanup_count -gt 0 ]]; then
        log_warn "Moved $cleanup_count leftover files to failed directory"
    fi
    
    log_info "Staging cleanup completed"
}

# Main execution
main() {
    # Create logs directory if needed
    mkdir -p "$LOGS_DIR"
    
    log_info "=== Media Processor Started ==="
    log_info "Staging directory: $STAGING_DIR"
    log_info "Log file: $LOG_FILE"
    
    # Check prerequisites
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    # Process media files
    process_movies
    process_tv_shows
    process_collections
    
    # Cleanup
    cleanup_staging
    
    log_info "=== Media Processor Completed ==="
}

# Handle script arguments
case "${1:-}" in
    --movies-only)
        log_info "Processing movies only"
        check_prerequisites && process_movies
        ;;
    --tv-only)
        log_info "Processing TV shows only"
        check_prerequisites && process_tv_shows
        ;;
    --collections-only)
        log_info "Processing Collections only"
        check_prerequisites && process_collections
        ;;
    --cleanup-only)
        log_info "Cleanup only"
        cleanup_staging
        ;;
    --help)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "OPTIONS:"
        echo "  --movies-only      Process only movies from Staging"
        echo "  --tv-only          Process only TV shows from Staging"
        echo "  --collections-only Process only Collections from Staging"
        echo "  --cleanup-only     Only cleanup empty directories and old logs"
        echo "  --help             Show this help message"
        echo ""
        echo "Default: Process all media types (movies, TV shows, collections)"
        ;;
    "")
        # No arguments provided - show usage
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "OPTIONS:"
        echo "  --movies-only      Process only movies from Staging"
        echo "  --tv-only          Process only TV shows from Staging"
        echo "  --collections-only Process only Collections from Staging"
        echo "  --cleanup-only     Only cleanup empty directories and old logs"
        echo "  --help             Show this help message"
        echo ""
        echo "Default: Process all media types (movies, TV shows, collections)"
        echo ""
        echo "To run processing, use: $0 --all"
        ;;
    --all)
        main
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac