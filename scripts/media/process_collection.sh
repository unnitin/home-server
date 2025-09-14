#!/usr/bin/env bash
set -euo pipefail

# Collection Processor - Handles Collections with exact folder structure preservation
# Collections maintain their original folder hierarchy and naming

COLLECTION_FILE="$1"
TARGET_DIR="$2"
LOG_FILE="${3:-/tmp/collection_processor.log}"
REL_PATH="${4:-$(basename "$1")}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [COLLECTION] [$level] $message" | tee -a "$LOG_FILE"
}

# Get file extension
get_extension() {
    local filename="$1"
    echo "${filename##*.}"
}

# Sanitize filename for filesystem (minimal changes for Collections)
sanitize_filename() {
    local name="$1"
    # Only remove truly problematic characters, preserve most formatting
    echo "$name" | sed 's/[<>:"|?*]//g'
}

# Process subtitle files
process_subtitles() {
    local collection_file="$1"
    local target_dir="$2"
    local file_basename="$3"
    
    local source_dir=$(dirname "$collection_file")
    local source_basename=$(basename "$collection_file" | sed 's/\.[^.]*$//')
    
    # Look for subtitle files with same basename
    find "$source_dir" -maxdepth 1 -name "${source_basename}.*" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.vtt" \) 2>/dev/null | while read -r subtitle_file; do
        local sub_ext=$(get_extension "$subtitle_file")
        local target_subtitle="$target_dir/$file_basename.$sub_ext"
        
        if mv "$subtitle_file" "$target_subtitle" 2>/dev/null; then
            log "INFO" "Moved subtitle: $(basename "$subtitle_file") -> $(basename "$target_subtitle")"
        else
            log "WARN" "Failed to move subtitle: $(basename "$subtitle_file")"
        fi
    done
}

# Process additional files (metadata, images, etc.)
process_additional_files() {
    local collection_file="$1"
    local target_dir="$2"
    local file_basename="$3"
    
    local source_dir=$(dirname "$collection_file")
    local source_basename=$(basename "$collection_file" | sed 's/\.[^.]*$//')
    
    # Look for additional files with same basename (images, metadata, etc.)
    find "$source_dir" -maxdepth 1 -name "${source_basename}.*" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.gif" -o -name "*.bmp" -o -name "*.nfo" -o -name "*.xml" -o -name "*.txt" \) 2>/dev/null | while read -r additional_file; do
        local add_ext=$(get_extension "$additional_file")
        local target_additional="$target_dir/$file_basename.$add_ext"
        
        if mv "$additional_file" "$target_additional" 2>/dev/null; then
            log "INFO" "Moved additional file: $(basename "$additional_file") -> $(basename "$target_additional")"
        else
            log "WARN" "Failed to move additional file: $(basename "$additional_file")"
        fi
    done
}

# Main processing function
process_collection() {
    local collection_file="$1"
    local target_base_dir="$2"
    local rel_path="$3"
    
    if [[ ! -f "$collection_file" ]]; then
        log "ERROR" "Collection file does not exist: $collection_file"
        return 1
    fi
    
    log "INFO" "Processing Collection item: $rel_path"
    
    # Get original filename and extension
    local original_filename=$(basename "$collection_file")
    local extension=$(get_extension "$collection_file")
    local file_basename=$(basename "$collection_file" | sed 's/\.[^.]*$//')
    
    # Sanitize filename (minimal changes for Collections)
    local sanitized_filename=$(sanitize_filename "$original_filename")
    local sanitized_basename=$(sanitize_filename "$file_basename")
    
    # Create target directory structure (preserve exact hierarchy)
    if ! mkdir -p "$target_base_dir"; then
        log "ERROR" "Failed to create directory: $target_base_dir"
        return 1
    fi
    
    # Create target path
    local target_path="$target_base_dir/$sanitized_filename"
    
    # Check if target already exists
    if [[ -f "$target_path" ]]; then
        log "WARN" "Target file already exists: $target_path"
        
        # Create alternative name with timestamp
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local name_without_ext="${sanitized_filename%.*}"
        sanitized_filename="${name_without_ext}_${timestamp}.$extension"
        target_path="$target_base_dir/$sanitized_filename"
        sanitized_basename="${name_without_ext}_${timestamp}"
        
        log "INFO" "Using alternative filename: $sanitized_filename"
    fi
    
    # Move the collection file
    if mv "$collection_file" "$target_path"; then
        log "SUCCESS" "Moved Collection item: $rel_path -> $target_path"
        
        # Process any associated subtitle files
        process_subtitles "$collection_file" "$target_base_dir" "$sanitized_basename"
        
        # Process any additional files (metadata, images, etc.)
        process_additional_files "$collection_file" "$target_base_dir" "$sanitized_basename"
        
        return 0
    else
        log "ERROR" "Failed to move Collection file: $collection_file -> $target_path"
        return 1
    fi
}

# Main execution
if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <collection_file> <target_directory> <log_file> [relative_path]"
    exit 1
fi

process_collection "$COLLECTION_FILE" "$TARGET_DIR" "$REL_PATH"
