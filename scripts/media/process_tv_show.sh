#!/usr/bin/env bash
set -euo pipefail

# TV Show Processor - Converts TV show files to Plex naming convention
# Expected Plex format: /TV Shows/Show Name (Year)/Season XX/Show Name - sXXeYY.ext

TV_FILE="$1"
TARGET_DIR="$2"
LOG_FILE="${3:-/tmp/tv_processor.log}"
REL_PATH="${4:-$(basename "$1")}"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [TV] [$level] $message" | tee -a "$LOG_FILE"
}

# Extract TV show information from filename
extract_tv_info() {
    local filename="$1"
    local basename=$(basename "$filename" | sed 's/\.[^.]*$//')  # Remove extension
    
    local show_name=""
    local year=""
    local season=""
    local episode=""
    local episode_title=""
    
    # Pattern 1: Current format - Show (Year) sXeXX - Episode Title
    if [[ "$basename" =~ ^(.+)\ \(([0-9]{4})\)\ s([0-9]+)e([0-9]+)\ -\ (.+)$ ]]; then
        show_name="${BASH_REMATCH[1]}"
        year="${BASH_REMATCH[2]}"
        season="${BASH_REMATCH[3]}"
        episode="${BASH_REMATCH[4]}"
        episode_title="${BASH_REMATCH[5]}"
    # Pattern 2: Show sXXeYY format
    elif [[ "$basename" =~ ^(.+)\ s([0-9]+)e([0-9]+).*$ ]]; then
        show_name="${BASH_REMATCH[1]}"
        season="${BASH_REMATCH[2]}"
        episode="${BASH_REMATCH[3]}"
    # Pattern 3: Show SXXeYY format (capital S)
    elif [[ "$basename" =~ ^(.+)\ S([0-9]+)E([0-9]+).*$ ]]; then
        show_name="${BASH_REMATCH[1]}"
        season="${BASH_REMATCH[2]}"
        episode="${BASH_REMATCH[3]}"
    # Pattern 4: Show.SXX.EYY format
    elif [[ "$basename" =~ ^(.+)\.S([0-9]+)\.E([0-9]+).*$ ]]; then
        show_name="${BASH_REMATCH[1]//./ }"  # Replace dots with spaces
        season="${BASH_REMATCH[2]}"
        episode="${BASH_REMATCH[3]}"
    # Pattern 5: Show - Season X Episode Y format
    elif [[ "$basename" =~ ^(.+)\ -\ Season\ ([0-9]+)\ Episode\ ([0-9]+).*$ ]]; then
        show_name="${BASH_REMATCH[1]}"
        season="${BASH_REMATCH[2]}"
        episode="${BASH_REMATCH[3]}"
    # Pattern 6: Show XxYY format
    elif [[ "$basename" =~ ^(.+)\ ([0-9]+)x([0-9]+).*$ ]]; then
        show_name="${BASH_REMATCH[1]}"
        season="${BASH_REMATCH[2]}"
        episode="${BASH_REMATCH[3]}"
    else
        log "WARN" "Could not parse TV show format: $basename"
        return 1
    fi
    
    # Clean up show name
    show_name=$(echo "$show_name" | sed 's/[._-]/ /g' | sed 's/^ *//;s/ *$//' | sed 's/  */ /g')
    
    # Remove quality indicators from show name
    show_name=$(echo "$show_name" | sed -E 's/\b(720p|1080p|4K|BluRay|BRrip|DVDrip|WEBrip|HDTV|x264|x265|HEVC|AAC|AC3|DTS)\b//gi' | sed 's/^ *//;s/ *$//' | sed 's/  */ /g')
    
    # Pad season and episode with zeros
    season=$(printf "%02d" "$season")
    episode=$(printf "%02d" "$episode")
    
    echo "$show_name|$year|$season|$episode|$episode_title"
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
    local tv_file="$1"
    local target_episode_dir="$2"
    local episode_basename="$3"
    
    local source_dir=$(dirname "$tv_file")
    local source_basename=$(basename "$tv_file" | sed 's/\.[^.]*$//')
    
    # Look for subtitle files with same basename
    find "$source_dir" -maxdepth 1 -name "${source_basename}.*" -type f \( -name "*.srt" -o -name "*.ass" -o -name "*.ssa" -o -name "*.vtt" \) | while read -r subtitle_file; do
        local sub_ext=$(get_extension "$subtitle_file")
        local target_subtitle="$target_episode_dir/$episode_basename.$sub_ext"
        
        if mv "$subtitle_file" "$target_subtitle" 2>/dev/null; then
            log "INFO" "Moved subtitle: $(basename "$subtitle_file") -> $(basename "$target_subtitle")"
        else
            log "WARN" "Failed to move subtitle: $(basename "$subtitle_file")"
        fi
    done
}

# Detect year from existing show directory or filename
detect_show_year() {
    local show_name="$1"
    local target_base_dir="$2"
    local filename="$3"
    
    # First, check if there's already a directory with this show name and year
    local existing_dir=$(find "$target_base_dir" -maxdepth 1 -type d -name "${show_name}*" | head -1)
    if [[ -n "$existing_dir" ]]; then
        local dir_basename=$(basename "$existing_dir")
        if [[ "$dir_basename" =~ \(([0-9]{4})\) ]]; then
            echo "${BASH_REMATCH[1]}"
            return 0
        fi
    fi
    
    # Try to extract year from filename
    if [[ "$filename" =~ ([0-9]{4}) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    
    # No year found
    echo ""
}

# Main processing function
process_tv_show() {
    local tv_file="$1"
    local target_base_dir="$2"
    
    if [[ ! -f "$tv_file" ]]; then
        log "ERROR" "TV file does not exist: $tv_file"
        return 1
    fi
    
    log "INFO" "Processing TV episode: $(basename "$tv_file")"
    
    # Extract TV show information
    local tv_info
    if ! tv_info=$(extract_tv_info "$tv_file"); then
        log "ERROR" "Failed to extract TV show information from: $(basename "$tv_file")"
        return 1
    fi
    
    local show_name=$(echo "$tv_info" | cut -d'|' -f1)
    local year=$(echo "$tv_info" | cut -d'|' -f2)
    local season=$(echo "$tv_info" | cut -d'|' -f3)
    local episode=$(echo "$tv_info" | cut -d'|' -f4)
    local episode_title=$(echo "$tv_info" | cut -d'|' -f5)
    local extension=$(get_extension "$tv_file")
    
    # Sanitize show name
    show_name=$(sanitize_filename "$show_name")
    
    if [[ -z "$show_name" || -z "$season" || -z "$episode" ]]; then
        log "ERROR" "Missing required information - Show: '$show_name', Season: '$season', Episode: '$episode'"
        return 1
    fi
    
    # Try to detect year if not found
    if [[ -z "$year" ]]; then
        year=$(detect_show_year "$show_name" "$target_base_dir" "$(basename "$tv_file")")
    fi
    
    # Create show directory name
    local show_dir_name
    if [[ -n "$year" ]]; then
        show_dir_name="$show_name ($year)"
    else
        show_dir_name="$show_name"
        log "WARN" "No year found for show: $show_name"
    fi
    
    # Create target directory structure
    local target_show_dir="$target_base_dir/$show_dir_name"
    local target_season_dir="$target_show_dir/Season $season"
    
    if ! mkdir -p "$target_season_dir"; then
        log "ERROR" "Failed to create directory: $target_season_dir"
        return 1
    fi
    
    # Create target filename in Plex format: Show Name - sXXeYY.ext
    local target_filename="$show_name - s${season}e${episode}.$extension"
    local target_path="$target_season_dir/$target_filename"
    
    # Check if target already exists
    if [[ -f "$target_path" ]]; then
        log "WARN" "Target file already exists: $target_path"
        # Create alternative name with timestamp
        local timestamp=$(date +%Y%m%d_%H%M%S)
        target_filename="$show_name - s${season}e${episode}_${timestamp}.$extension"
        target_path="$target_season_dir/$target_filename"
        log "INFO" "Using alternative filename: $target_filename"
    fi
    
    # Move the TV file
    if mv "$tv_file" "$target_path"; then
        log "SUCCESS" "Moved episode: $(basename "$tv_file") -> $target_path"
        
        # Process any associated subtitle files
        process_subtitles "$tv_file" "$target_season_dir" "${target_filename%.*}"
        
        return 0
    else
        log "ERROR" "Failed to move TV file: $tv_file -> $target_path"
        return 1
    fi
}

# Main execution
if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <tv_file> <target_directory> [log_file] [relative_path]"
    exit 1
fi

process_tv_show "$TV_FILE" "$TARGET_DIR"
