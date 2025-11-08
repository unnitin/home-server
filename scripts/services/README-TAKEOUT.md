# Quick Start: Enhanced Google Photos Takeout Import

## TL;DR

```bash
# Process all takeout data with metadata preservation and upload to Immich
export IMMICH_SERVER="http://localhost:2283"
export IMMICH_API_KEY="your-api-key"

./enhanced_takeout_import.sh \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir ./tmp/takeout-processed
```

## What This Does

1. **Extracts** all 84 takeout zip files from `/Volumes/faststore/takeout-downloads`
2. **Preserves metadata** including GPS coordinates, timestamps, descriptions
3. **Embeds metadata** into image EXIF and video metadata streams
4. **Maintains album structure** from Google Photos
5. **Uploads to Immich** with proper organization

## Files Created

- `enhanced_takeout_import.py` - Main processing engine
- `enhanced_takeout_import.sh` - User-friendly wrapper script
- `requirements-takeout.txt` - Python dependencies

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

## Prerequisites


```bash
# Install dependencies
pip install -r requirements-takeout.txt
brew install ffmpeg

# Get immich-go
# Download from: https://github.com/immich-app/immich-go/releases
```

For detailed documentation, see: [docs/TAKEOUT-IMPORT.md](../../docs/TAKEOUT-IMPORT.md)

