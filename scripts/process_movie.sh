#!/usr/bin/env bash
set -euo pipefail

# Movie Processor - Converts movie files to Plex naming convention
# Expected Plex format: /Movies/Movie Name (Year)/Movie Name (Year).ext

MOVIE_FILE="$1"
TARGET_DIR="$2"
LOG_FILE="${3:-/tmp/movie_processor.log}"
REL_PATH="${4:-$(basename "$1")}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [MOVIE] [$level] $message" | tee -a "$LOG_FILE"
}

# Extract movie information from filename
extract_movie_info() {
    local filename="$1"
    local basename=$(basename "$filename" | sed 's/\.[^.]*$//')  # Remove extension
    
    # Common patterns to extract title and year
    local title=""
    local year=""
    
    # Pattern 1: Title (Year) format
    if [[ "$basename" =~ ^(.+)\ \(([0-9]{4})\).*$ ]]; then
        title="${BASH_REMATCH[1]}"
        year="${BASH_REMATCH[2]}"
    # Pattern 2: Title.Year format
    elif [[ "$basename" =~ ^(.+)\.([0-9]{4}).*$ ]]; then
        title="${BASH_REMATCH[1]//./ }"  # Replace dots with spaces
        year="${BASH_REMATCH[2]}"
    # Pattern 3: Title Year format (space separated)
    elif [[ "$basename" =~ ^(.+)\ ([0-9]{4}).*$ ]]; then
        title="${BASH_REMATCH[1]}"
        year="${BASH_REMATCH[2]}"
    # Pattern 4: Try to extract year from anywhere in the filename
    elif [[ "$basename" =~ ([0-9]{4}) ]]; then
        year="${BASH_REMATCH[1]}"
        title=$(echo "$basename" | sed "s/$year//g" | sed 's/[._-]/ /g' | sed 's/^ *//;s/ *$//')
    else
        # No year found, use entire basename as title
        title=$(echo "$basename" | sed 's/[._-]/ /g' | sed 's/^ *//;s/ *$//')
        year=""
    fi
    
    # Clean up title
    title=$(echo "$title" | sed 's/[._-]/ /g' | sed 's/^ *//;s/ *$//' | sed 's/  */ /g')
    
    # Remove common quality indicators and release info
    title=$(echo "$title" | sed -E 's/\b(720p|1080p|4K|BluRay|BRrip|DVDrip|WEBrip|HDTV|x264|x265|HEVC|AAC|AC3|DTS)\b//gi' | sed 's/^ *//;s/ *$//' | sed 's/  */ /g')
    
    echo "$title|$year"
}

# Sanitize filename for filesystem
sanitize_filename() {
    local name="$1"
    # Remove or replace problematic characters
    echo "$name" | sed 's/[<>:"/\\|?*]//g' | sed 's/  */ /g' | sed 's/^ *//;s/ *$//'
}

# Get file extension
get_extension() {
    local filename="$1"
    echo "${filename##*.}"
}

# Process subtitle files
process_subtitles() {
    local movie_file="$1"
    local target_movie_dir="$2"
    local movie_basename="$3"
    
    local source_dir=$(dirname "$movie_file")
    local source_basename=$(basename "$movie_file" | sed 's/\.[^.]*$//')
    
    # Look for subtitle files with same basename
    find "$source_dir" -maxdepth 1 -name "${source_basename}.*" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.vtt" \) | while read -r subtitle_file; do
        local sub_ext=$(get_extension "$subtitle_file")
        local target_subtitle="$target_movie_dir/$movie_basename.$sub_ext"
        
        if mv "$subtitle_file" "$target_subtitle" 2>/dev/null; then
            log "INFO" "Moved subtitle: $(basename "$subtitle_file") -> $(basename "$target_subtitle")"
        else
            log "WARN" "Failed to move subtitle: $(basename "$subtitle_file")"
        fi
    done
}

# Main processing function
process_movie() {
    local movie_file="$1"
    local target_base_dir="$2"
    
    if [[ ! -f "$movie_file" ]]; then
        log "ERROR" "Movie file does not exist: $movie_file"
        return 1
    fi
    
    log "INFO" "Processing movie: $(basename "$movie_file")"
    
    # Extract movie information
    local movie_info=$(extract_movie_info "$movie_file")
    local title=$(echo "$movie_info" | cut -d'|' -f1)
    local year=$(echo "$movie_info" | cut -d'|' -f2)
    local extension=$(get_extension "$movie_file")
    
    # Sanitize title
    title=$(sanitize_filename "$title")
    
    if [[ -z "$title" ]]; then
        log "ERROR" "Could not extract movie title from: $(basename "$movie_file")"
        return 1
    fi
    
    # Create movie directory name
    local movie_dir_name
    if [[ -n "$year" ]]; then
        movie_dir_name="$title ($year)"
    else
        movie_dir_name="$title"
        log "WARN" "No year found for movie: $title"
    fi
    
    # Create target directory structure
    local target_movie_dir="$target_base_dir/$movie_dir_name"
    if ! mkdir -p "$target_movie_dir"; then
        log "ERROR" "Failed to create directory: $target_movie_dir"
        return 1
    fi
    
    # Create target filename
    local target_filename="$movie_dir_name.$extension"
    local target_path="$target_movie_dir/$target_filename"
    
    # Check if target already exists
    if [[ -f "$target_path" ]]; then
        log "WARN" "Target file already exists: $target_path"
        # Create alternative name with timestamp
        local timestamp=$(date +%Y%m%d_%H%M%S)
        target_filename="${movie_dir_name}_${timestamp}.$extension"
        target_path="$target_movie_dir/$target_filename"
        log "INFO" "Using alternative filename: $target_filename"
    fi
    
    # Move the movie file
    if mv "$movie_file" "$target_path"; then
        log "SUCCESS" "Moved movie: $(basename "$movie_file") -> $target_path"
        
        # Process any associated subtitle files
        process_subtitles "$movie_file" "$target_movie_dir" "${target_filename%.*}"
        
        return 0
    else
        log "ERROR" "Failed to move movie file: $movie_file -> $target_path"
        return 1
    fi
}

# Main execution
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <movie_file> <target_directory> [log_file] [relative_path]"
    exit 1
fi

process_movie "$MOVIE_FILE" "$TARGET_DIR"
