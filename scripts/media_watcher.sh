#!/usr/bin/env bash
set -euo pipefail

# Media Watcher - Monitors Staging directories for new files and triggers processing
# Uses fswatch to monitor file system events

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
WARMSTORE="/Volumes/warmstore"
STAGING_DIR="$WARMSTORE/Staging"
MOVIES_STAGING="$STAGING_DIR/Movies"
TV_STAGING="$STAGING_DIR/TV Shows"
COLLECTIONS_STAGING="$STAGING_DIR/Collections"
LOGS_DIR="$WARMSTORE/logs/media-watcher"

# Watcher configuration
WATCH_DELAY=30  # Wait 30 seconds after file changes before processing
LOCK_FILE="/tmp/media_watcher.lock"
PID_FILE="/tmp/media_watcher.pid"

# Logging setup
LOG_FILE="$LOGS_DIR/media_watcher.log"
mkdir -p "$LOGS_DIR"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [WATCHER] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }

# Check if fswatch is available
check_fswatch() {
    if ! command -v fswatch >/dev/null 2>&1; then
        log_error "fswatch not found. Install with: brew install fswatch"
        echo "Alternative: Use --poll mode for basic polling"
        return 1
    fi
    return 0
}

# Process files after delay
process_with_delay() {
    local changed_path="$1"
    
    log_info "File change detected: $changed_path"
    
    # Wait for file to stabilize (in case it's still being written)
    sleep "$WATCH_DELAY"
    
    # Check if file still exists and is a media file
    if [[ ! -f "$changed_path" ]]; then
        log_info "File no longer exists, skipping: $changed_path"
        return 0
    fi
    
    # Check file extension
    local extension="${changed_path##*.}"
    case "${extension,,}" in
        mkv|mp4|avi|mov|m4v|wmv|flv|webm)
            log_info "Processing media file: $(basename "$changed_path")"
            
            # Acquire lock to prevent concurrent processing
            if ! acquire_lock; then
                log_warn "Another processing instance is running, skipping: $(basename "$changed_path")"
                return 0
            fi
            
            # Run media processor
            if "$SCRIPT_DIR/media_processor.sh"; then
                log_info "Media processing completed successfully"
            else
                log_error "Media processing failed"
            fi
            
            release_lock
            ;;
        *)
            log_info "Ignoring non-media file: $(basename "$changed_path")"
            ;;
    esac
}

# Lock management
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            return 1  # Lock is held by running process
        else
            # Stale lock file
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    return 0
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# Cleanup function
cleanup() {
    log_info "Shutting down media watcher..."
    release_lock
    rm -f "$PID_FILE"
    exit 0
}

# Signal handlers
trap cleanup SIGTERM SIGINT

# Start fswatch monitoring
start_fswatch() {
    log_info "Starting fswatch monitoring..."
    log_info "Monitoring directories: $MOVIES_STAGING, $TV_STAGING, $COLLECTIONS_STAGING"
    
    # Create directories if they don't exist
    mkdir -p "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
    # Start fswatch
    fswatch -r -e ".*" -i "\\.mkv$|\\.mp4$|\\.avi$|\\.mov$|\\.m4v$|\\.wmv$|\\.flv$|\\.webm$" \
        "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING" | while read -r changed_path; do
        
        # Process in background to avoid blocking fswatch
        process_with_delay "$changed_path" &
    done
}

# Polling mode (fallback when fswatch is not available)
start_polling() {
    log_info "Starting polling mode (checking every 60 seconds)..."
    log_info "Monitoring directories: $MOVIES_STAGING, $TV_STAGING, $COLLECTIONS_STAGING"
    
    # Create directories if they don't exist
    mkdir -p "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING"
    
    # Store PID
    echo $$ > "$PID_FILE"
    
    local last_check_file="/tmp/media_watcher_last_check"
    
    while true; do
        # Find files newer than last check
        local current_time=$(date +%s)
        
        if [[ -f "$last_check_file" ]]; then
            local last_check=$(cat "$last_check_file")
        else
            local last_check=$((current_time - 60))
        fi
        
        # Check for new files
        find "$MOVIES_STAGING" "$TV_STAGING" "$COLLECTIONS_STAGING" -type f -newer "$last_check_file" 2>/dev/null \
            \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" -o -name "*.mov" -o -name "*.m4v" -o -name "*.wmv" -o -name "*.flv" -o -name "*.webm" \) | while read -r new_file; do
            
            log_info "New file detected: $(basename "$new_file")"
            
            # Acquire lock to prevent concurrent processing
            if acquire_lock; then
                # Run media processor
                if "$SCRIPT_DIR/media_processor.sh"; then
                    log_info "Media processing completed successfully"
                else
                    log_error "Media processing failed"
                fi
                release_lock
            else
                log_warn "Another processing instance is running, will retry next cycle"
            fi
        done
        
        # Update last check time
        echo "$current_time" > "$last_check_file"
        
        # Wait before next check
        sleep 60
    done
}

# Check if already running
check_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Media watcher is already running (PID: $pid)"
            exit 1
        else
            # Stale PID file
            rm -f "$PID_FILE"
        fi
    fi
}

# Stop running watcher
stop_watcher() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping media watcher (PID: $pid)"
            kill "$pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                log_warn "Process still running, force killing..."
                kill -9 "$pid"
            fi
            rm -f "$PID_FILE"
            log_info "Media watcher stopped"
        else
            log_warn "No running media watcher found"
            rm -f "$PID_FILE"
        fi
    else
        log_warn "No PID file found"
    fi
}

# Show status
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Media watcher is running (PID: $pid)"
            echo "Log file: $LOG_FILE"
            echo "Monitoring: $MOVIES_STAGING, $TV_STAGING, $COLLECTIONS_STAGING"
        else
            echo "Media watcher is not running (stale PID file)"
            rm -f "$PID_FILE"
        fi
    else
        echo "Media watcher is not running"
    fi
}

# Main execution
case "${1:-start}" in
    start)
        check_running
        log_info "=== Media Watcher Starting ==="
        if check_fswatch; then
            start_fswatch
        else
            log_warn "Falling back to polling mode"
            start_polling
        fi
        ;;
    stop)
        stop_watcher
        ;;
    restart)
        stop_watcher
        sleep 2
        check_running
        log_info "=== Media Watcher Restarting ==="
        if check_fswatch; then
            start_fswatch
        else
            start_polling
        fi
        ;;
    status)
        show_status
        ;;
    --poll)
        check_running
        log_info "=== Media Watcher Starting (Polling Mode) ==="
        start_polling
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|--poll}"
        echo ""
        echo "Commands:"
        echo "  start    - Start the media watcher (uses fswatch if available)"
        echo "  stop     - Stop the media watcher"
        echo "  restart  - Restart the media watcher"
        echo "  status   - Show watcher status"
        echo "  --poll   - Start in polling mode (fallback when fswatch unavailable)"
        exit 1
        ;;
esac
