#!/usr/bin/env bash
set -euo pipefail

# Enhanced Google Photos Takeout Import Script for Immich
# Usage: ./enhanced_takeout_import.sh [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
TAKEOUT_DIR="/Volumes/faststore/takeout-downloads"
OUTPUT_DIR="/Volumes/faststore/tmp/takeout-processed"
IMMICH_SERVER="${IMMICH_SERVER:-}"
IMMICH_API_KEY="${IMMICH_API_KEY:-}"
SKIP_UPLOAD=false
SKIP_DEPS=false
SKIP_SYSTEM_DEPS=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    cat << EOF
Enhanced Google Photos Takeout Import Script for Immich

Usage: $0 [OPTIONS]

OPTIONS:
    -i, --takeout-dir DIR      Directory containing takeout zip files (default: $TAKEOUT_DIR)
    -o, --output-dir DIR       Output directory for processed files (default: $OUTPUT_DIR)
    -s, --immich-server URL    Immich server URL (e.g., http://localhost:2283)
    -k, --api-key KEY          Immich API key
    --skip-upload             Skip upload to Immich (only process files)
    --skip-deps               Skip Python dependency installation
    --skip-system-deps        Skip system dependency installation (ffmpeg, immich-go)
    -h, --help                Show this help message

ENVIRONMENT VARIABLES:
    IMMICH_SERVER             Immich server URL (can be overridden by -s)
    IMMICH_API_KEY            Immich API key (can be overridden by -k)

EXAMPLES:
    # Process only (no upload)
    $0 --skip-upload

    # Process and upload to Immich
    $0 -s http://localhost:2283 -k your-api-key

    # Use custom directories
    $0 -i /path/to/takeout -o /path/to/output

    # Skip all dependency installation
    $0 --skip-deps --skip-system-deps

EOF
}

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

install_system_dependencies() {
    if [[ "$SKIP_SYSTEM_DEPS" == true ]]; then
        log "Skipping system dependency installation"
        return 0
    fi
    
    log "Installing system dependencies..."
    
    # Check if we're on macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script currently only supports macOS. Please install ffmpeg and immich-go manually."
        return 1
    fi
    
    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        error "Homebrew is required but not installed. Please install from https://brew.sh"
        return 1
    fi
    
    # Install ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        log "Installing ffmpeg..."
        if brew install ffmpeg; then
            success "ffmpeg installed successfully"
        else
            error "Failed to install ffmpeg"
            return 1
        fi
    else
        success "ffmpeg already installed"
    fi
    
    # Install immich-go if not present
    if ! command -v immich-go &> /dev/null; then
        log "Installing immich-go..."
        
        # Try Homebrew tap first
        if brew install immich-app/immich-go/immich-go 2>/dev/null; then
            success "immich-go installed successfully via Homebrew"
        else
            log "Homebrew tap failed, installing via direct download..."
            
            # Determine architecture
            local arch
            if [[ "$(uname -m)" == "arm64" ]]; then
                arch="arm64"
            else
                arch="amd64"
            fi
            
            # Download and install immich-go binary directly
            local download_url="https://github.com/immich-app/immich-go/releases/latest/download/immich-go_Darwin_${arch}.tar.gz"
            local temp_dir=$(mktemp -d)
            
            if curl -L -o "$temp_dir/immich-go.tar.gz" "$download_url" && \
               tar -xzf "$temp_dir/immich-go.tar.gz" -C "$temp_dir" && \
               sudo mv "$temp_dir/immich-go" /usr/local/bin/ && \
               chmod +x /usr/local/bin/immich-go; then
                success "immich-go installed successfully via direct download"
                rm -rf "$temp_dir"
            else
                error "Failed to install immich-go. Please install manually from:"
                error "https://github.com/immich-app/immich-go/releases"
                rm -rf "$temp_dir"
                return 1
            fi
        fi
    else
        success "immich-go already installed"
    fi
    
    return 0
}

check_prerequisites() {
    log "Checking prerequisites..."
    
    # Install system dependencies first
    if ! install_system_dependencies; then
        return 1
    fi
    
    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed"
        return 1
    fi
    
    local python_version
    python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    log "Found Python $python_version"
    
    # Check if we're in a virtual environment or can create one
    if [[ -z "${VIRTUAL_ENV:-}" ]]; then
        if [[ -d "$PROJECT_ROOT/venv" ]]; then
            log "Activating existing virtual environment..."
            source "$PROJECT_ROOT/venv/bin/activate"
        else
            log "Creating virtual environment..."
            python3 -m venv "$PROJECT_ROOT/venv"
            source "$PROJECT_ROOT/venv/bin/activate"
        fi
    fi
    
    # Install Python dependencies if not skipping
    if [[ "$SKIP_DEPS" != true ]]; then
        log "Installing Python dependencies (v4.0 with pillow-heif and enhanced validation)..."
        pip install --quiet --upgrade pip
        
        # Install from requirements file in takeout submodule
        if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
            pip install --quiet -r "$SCRIPT_DIR/requirements.txt"
        else
            # Fallback to individual packages including new ones
            pip install --quiet piexif pillow ffmpeg-python pillow-heif
        fi
        
        # Install exiftool if available (optional, for advanced HEIC processing)
        if command -v brew >/dev/null 2>&1; then
            log "Installing exiftool for advanced metadata handling..."
            if ! brew list exiftool >/dev/null 2>&1; then
                brew install exiftool || log "⚠️  exiftool installation failed (optional, continuing without it)"
            else
                log "exiftool already installed"
            fi
        fi
        
        success "Python dependencies installed with v4.0 enhancements"
    fi
    
    # Verify critical dependencies
    log "Verifying dependencies..."
    
    # Check ffmpeg
    if ! command -v ffmpeg &> /dev/null; then
        warning "ffmpeg not found. Video metadata processing will be limited."
        warning "Install with: brew install ffmpeg"
    else
        success "ffmpeg found: $(ffmpeg -version | head -1)"
    fi
    
    # Check immich-go if upload is requested
    if [[ "$SKIP_UPLOAD" != true ]]; then
        if ! command -v immich-go &> /dev/null; then
            warning "immich-go not found. Upload functionality will be limited."
            warning "Install from: https://github.com/immich-app/immich-go"
        else
            success "immich-go found: $(immich-go --version 2>/dev/null || echo 'version unknown')"
        fi
    fi
    
    return 0
}

validate_inputs() {
    log "Validating inputs..."
    
    # Check takeout directory
    if [[ ! -d "$TAKEOUT_DIR" ]]; then
        error "Takeout directory does not exist: $TAKEOUT_DIR"
        return 1
    fi
    
    # Check for zip files
    if ! ls "$TAKEOUT_DIR"/*.zip &> /dev/null; then
        error "No zip files found in takeout directory: $TAKEOUT_DIR"
        return 1
    fi
    
    local zip_count
    zip_count=$(ls -1 "$TAKEOUT_DIR"/*.zip | wc -l | tr -d ' ')
    log "Found $zip_count zip files to process"
    
    # Validate Immich settings if upload is requested
    if [[ "$SKIP_UPLOAD" != true ]]; then
        if [[ -z "$IMMICH_SERVER" ]] || [[ -z "$IMMICH_API_KEY" ]]; then
            warning "Immich server or API key not provided. Upload will be skipped."
            SKIP_UPLOAD=true
        else
            log "Immich upload configured: $IMMICH_SERVER"
        fi
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    success "Output directory ready: $OUTPUT_DIR"
    
    return 0
}

estimate_space() {
    log "Estimating space requirements..."
    
    local takeout_size
    takeout_size=$(du -sh "$TAKEOUT_DIR" | cut -f1)
    log "Takeout data size: $takeout_size"
    
    local available_space
    available_space=$(df -h "$OUTPUT_DIR" | awk 'NR==2 {print $4}')
    log "Available space: $available_space"
    
    warning "Estimated space needed: ~2-3x takeout size (for extraction and processing)"
}

run_processor() {
    log "Starting enhanced takeout processing..."
    
    local cmd_args=(
        "--takeout-dir" "$TAKEOUT_DIR"
        "--output-dir" "$OUTPUT_DIR"
    )
    
    if [[ "$SKIP_UPLOAD" != true ]]; then
        cmd_args+=("--immich-server" "$IMMICH_SERVER")
        cmd_args+=("--api-key" "$IMMICH_API_KEY")
    else
        cmd_args+=("--skip-upload")
    fi
    
    # Run the Python processor
    python3 "$SCRIPT_DIR/enhanced_takeout_import.py" "${cmd_args[@]}"
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        success "Processing completed successfully!"
        log "Processed files are available in: $OUTPUT_DIR/processed"
        
        if [[ "$SKIP_UPLOAD" == true ]]; then
            log ""
            log "To upload to Immich later, you can use:"
            log "  immich-go upload --server YOUR_SERVER --api-key YOUR_KEY --album-from-folder $OUTPUT_DIR/processed"
        fi
    else
        error "Processing failed. Check the logs for details."
        return $exit_code
    fi
}

cleanup() {
    log "Cleaning up temporary files..."
    
    # Remove extraction directory but keep processed files
    if [[ -d "$OUTPUT_DIR/extracted" ]]; then
        rm -rf "$OUTPUT_DIR/extracted"
        log "Temporary extraction files removed"
    fi
}

show_banner() {
    echo ""
    echo "================================================"
    echo "  Enhanced Google Photos Takeout Import"
    echo "           for Immich with Metadata"
    echo "                 v2.0"
    echo "================================================"
    echo ""
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--takeout-dir)
                TAKEOUT_DIR="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -s|--immich-server)
                IMMICH_SERVER="$2"
                shift 2
                ;;
            -k|--api-key)
                IMMICH_API_KEY="$2"
                shift 2
                ;;
            --skip-upload)
                SKIP_UPLOAD=true
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=true
                shift
                ;;
            --skip-system-deps)
                SKIP_SYSTEM_DEPS=true
                shift
                ;;
            -h|--help)
                print_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    show_banner
    
    # Run the processing pipeline
    if ! check_prerequisites; then
        error "Prerequisites check failed"
        exit 1
    fi
    
    if ! validate_inputs; then
        error "Input validation failed"
        exit 1
    fi
    
    estimate_space
    
    # Confirm before proceeding (only if running interactively)
    if [[ -t 0 ]]; then  # Check if running interactively
        echo ""
        read -p "Proceed with processing? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Processing cancelled by user"
            exit 0
        fi
    fi
    
    if ! run_processor; then
        error "Processing failed"
        exit 1
    fi
    
    cleanup
    
    success "All done! Your Google Photos are ready for Immich."
}

# Handle script interruption
trap 'error "Script interrupted"; exit 130' INT TERM

# Run main function
main "$@"
