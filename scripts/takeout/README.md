# Enhanced Google Photos Takeout Import for Immich

A comprehensive solution for importing Google Photos takeout data into Immich with full metadata preservation, including GPS coordinates, original timestamps, device information, and album structure.

## 🚀 Quick Start

```bash
# Navigate to the takeout directory
cd /Users/nitinsrivastava/Documents/home-server/scripts/takeout

# Process all takeout data with metadata preservation and upload to Immich
export IMMICH_SERVER="http://localhost:2283"  
export IMMICH_API_KEY="your-api-key"

./enhanced_takeout_import.sh \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir /Volumes/faststore/tmp/takeout-processed
```

## What This Does

1. **Extracts** all 84 takeout zip files from `/Volumes/faststore/takeout-downloads`
2. **Preserves metadata** including GPS coordinates, timestamps, descriptions
3. **Embeds metadata** into image EXIF and video metadata streams
4. **Maintains album structure** from Google Photos
5. **Uploads to Immich** with proper organization

## 📁 Files in This Module

- `enhanced_takeout_import.py` - Main processing engine (421 lines)
- `enhanced_takeout_import.sh` - User-friendly wrapper script with auto-dependency installation
- `requirements.txt` - Python dependencies (piexif, pillow, ffmpeg-python)
- `DOCUMENTATION.md` - Comprehensive technical documentation
- `TEST-RESULTS.md` - Validation results and test data
- `README.md` - This quick start guide

## Quick Commands

```bash
# Process only (no upload)
./enhanced_takeout_import.sh --skip-upload

# Process with custom directories
./enhanced_takeout_import.sh \
    -i /custom/takeout/path \
    -o /custom/output/path

# Process and upload with explicit credentials
./enhanced_takeout_import.sh \
    -s http://immich-server:2283 \
    -k your-api-key-here
```

## Expected Results

- **~15,000+ photos/videos** processed with full metadata
- **~127 albums** recreated in Immich
- **GPS coordinates** preserved for location-tagged photos
- **Original timestamps** maintained from photo capture time
- **Complete processing logs** in `takeout_import.log`

## ✨ New Features

- **🔧 Automatic Dependency Installation**: Script now automatically installs ffmpeg and immich-go via Homebrew
- **📁 Organized File Structure**: All takeout-related files moved to `scripts/takeout/` submodule  
- **🚀 Enhanced Setup Process**: One command handles all prerequisites
- **📊 Comprehensive Testing**: Validated with real takeout data (84GB, 35,000+ files)

## Prerequisites

The script now handles most prerequisites automatically! You just need:

- **macOS** (with Homebrew installed)
- **Python 3.8+** (usually pre-installed)

### Automatic Installation
The script will automatically install:
- **ffmpeg** (for video metadata processing)
- **immich-go** (for optimized uploads)
- **Python packages** (piexif, pillow, ffmpeg-python)

### Manual Installation (if needed)
```bash
# If you prefer manual installation or the auto-install fails:
brew install ffmpeg
brew install immich-app/immich-go/immich-go
pip install -r requirements.txt
```

## 📚 Documentation

For detailed technical documentation, see: [DOCUMENTATION.md](./DOCUMENTATION.md)

For test results and validation details, see: [TEST-RESULTS.md](./TEST-RESULTS.md)

