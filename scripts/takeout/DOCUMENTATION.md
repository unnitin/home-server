# Enhanced Google Photos Takeout Import for Immich

This document details the comprehensive solution for importing Google Photos takeout data into Immich while preserving maximum metadata fidelity.

## Table of Contents

1. [Overview](#overview)
2. [Data Structure Analysis](#data-structure-analysis)
3. [Solution Architecture](#solution-architecture)
4. [Implementation Details](#implementation-details)
5. [Usage Guide](#usage-guide)
6. [Metadata Mapping](#metadata-mapping)
7. [Troubleshooting](#troubleshooting)

## Overview

Google Photos takeout data comes with rich metadata stored in JSON files alongside each media file. The standard takeout import scripts often ignore this valuable metadata. Our enhanced solution:

- **Preserves complete metadata** from Google Photos JSON files
- **Embeds metadata into media files** using EXIF for images and metadata streams for videos
- **Maintains album structure** during import to Immich
- **Handles large takeout archives** efficiently with batch processing
- **Provides comprehensive logging** and error handling

### Key Features

- ✅ GPS coordinates preservation
- ✅ Original timestamp preservation
- ✅ Description and title metadata
- ✅ Device information
- ✅ Album structure maintenance
- ✅ Batch processing of multiple zip files
- ✅ Direct Immich upload integration
- ✅ Comprehensive error handling and logging

## Data Structure Analysis

### Google Photos Takeout Structure

```
Takeout/
└── Google Photos/
    ├── Album Name 1/
    │   ├── IMG_20230101_120000.jpg
    │   ├── IMG_20230101_120000.jpg.supplemental-metadata.json
    │   ├── VID_20230102_150000.mp4
    │   ├── VID_20230102_150000.mp4.supplemental-metadata.json
    │   └── metadata.json  # Album-level metadata
    ├── Album Name 2/
    └── user-generated-memory-titles.json
```

### Metadata Schema Analysis

Based on analysis of the takeout data at `/Volumes/faststore/takeout-downloads`, we identified the following metadata structure:

#### Individual File Metadata (`.supplemental-metadata.json`)

```json
{
  "title": "IMG_20180722_114642.jpg",
  "description": "",
  "imageViews": "3",
  "creationTime": {
    "timestamp": "1532389819",
    "formatted": "Jul 23, 2018, 11:50:19 PM UTC"
  },
  "photoTakenTime": {
    "timestamp": "1532281602",
    "formatted": "Jul 22, 2018, 5:46:42 PM UTC"
  },
  "geoData": {
    "latitude": 40.399288899999995,
    "longitude": -105.8353333,
    "altitude": 3061.0,
    "latitudeSpan": 0.0,
    "longitudeSpan": 0.0
  },
  "geoDataExif": {
    "latitude": 40.399288899999995,
    "longitude": -105.8353333,
    "altitude": 3061.0,
    "latitudeSpan": 0.0,
    "longitudeSpan": 0.0
  },
  "url": "https://photos.google.com/photo/...",
  "googlePhotosOrigin": {
    "mobileUpload": {
      "deviceFolder": {
        "localFolderName": ""
      },
      "deviceType": "ANDROID_PHONE"
    }
  }
}
```

#### Album Metadata (`metadata.json`)

```json
{
  "title": "Weekend in Grand County",
  "description": "",
  "access": "protected",
  "date": {
    "timestamp": "1532201594",
    "formatted": "Jul 21, 2018, 7:33:14 PM UTC"
  },
  "enrichments": [
    {
      "mapEnrichment": {
        "origin": [{"name": "Irvine", "description": "California"}],
        "destination": [{"name": "Grand Lake", "description": "Colorado"}]
      }
    }
  ]
}
```

## Solution Architecture

### Components Overview

```
┌─────────────────────┐    ┌──────────────────────┐    ┌─────────────────┐
│   Takeout Zips      │    │   Processing Engine  │    │   Immich        │
│   (84 files)        │───▶│                      │───▶│   Server        │
│                     │    │   • Extract          │    │                 │
│   /Volumes/faststore│    │   • Parse Metadata   │    │   Albums +      │
│   /takeout-downloads│    │   • Embed EXIF/XMP   │    │   Metadata      │
└─────────────────────┘    │   • Upload           │    └─────────────────┘
                           └──────────────────────┘
```

### Processing Pipeline

1. **Archive Extraction**: Extract all takeout zip files to temporary directory
2. **Metadata Parsing**: Read and parse JSON metadata files
3. **Media Processing**: 
   - **Images**: Embed metadata into EXIF data using `piexif`
   - **Videos**: Embed metadata using `ffmpeg`
4. **Album Structure**: Maintain original album organization
5. **Immich Upload**: Upload processed files with `immich-go`

### File Organization

```
scripts/services/
├── enhanced_takeout_import.py      # Main Python processor
├── enhanced_takeout_import.sh      # Bash wrapper script
└── import_takeout.sh              # Original simple script

requirements-takeout.txt            # Python dependencies
docs/TAKEOUT-IMPORT.md              # This documentation
```

## Implementation Details

### Core Classes and Functions

#### TakeoutProcessor Class

The main processing engine with the following key methods:

```python
class TakeoutProcessor:
    def __init__(self, takeout_dir, output_dir, immich_server=None, api_key=None):
        """Initialize processor with configuration."""
        
    def extract_archives(self):
        """Extract all takeout zip files."""
        
    def parse_metadata(self, json_path):
        """Parse Google Photos JSON metadata."""
        
    def process_image_metadata(self, image_path, metadata, output_path):
        """Embed metadata into image EXIF data."""
        
    def process_video_metadata(self, video_path, metadata, output_path):
        """Embed metadata into video using ffmpeg."""
        
    def upload_to_immich(self):
        """Upload processed files to Immich."""
```

#### Key Metadata Processing Functions

##### GPS Coordinate Embedding

```python
def set_gps_exif(self, exif_dict: Dict, latitude: float, longitude: float, altitude: float = None):
    """Set GPS information in EXIF data."""
    def decimal_to_dms(decimal_deg):
        degrees = int(abs(decimal_deg))
        minutes_float = (abs(decimal_deg) - degrees) * 60
        minutes = int(minutes_float)
        seconds = (minutes_float - minutes) * 60
        return ((degrees, 1), (minutes, 1), (int(seconds * 100), 100))
    
    gps_ifd = {}
    gps_ifd[piexif.GPSIFD.GPSLatitude] = decimal_to_dms(latitude)
    gps_ifd[piexif.GPSIFD.GPSLatitudeRef] = 'N' if latitude >= 0 else 'S'
    gps_ifd[piexif.GPSIFD.GPSLongitude] = decimal_to_dms(longitude)
    gps_ifd[piexif.GPSIFD.GPSLongitudeRef] = 'E' if longitude >= 0 else 'W'
    
    if altitude is not None:
        gps_ifd[piexif.GPSIFD.GPSAltitude] = (int(altitude * 100), 100)
        gps_ifd[piexif.GPSIFD.GPSAltitudeRef] = 0  # Above sea level
    
    exif_dict['GPS'] = gps_ifd
```

##### Timestamp Conversion

```python
def convert_timestamp_to_exif(self, timestamp: str) -> str:
    """Convert Unix timestamp to EXIF date format."""
    try:
        dt = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
        return dt.strftime('%Y:%m:%d %H:%M:%S')
    except (ValueError, TypeError):
        return ""
```

##### Video Metadata Processing

```python
def process_video_metadata(self, video_path: Path, metadata: Dict, output_path: Path) -> bool:
    """Process and embed metadata into video file using ffmpeg."""
    ffmpeg_metadata = {}
    
    # Set creation time
    if 'photoTakenTime' in metadata:
        timestamp = metadata['photoTakenTime'].get('timestamp')
        if timestamp:
            dt = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
            ffmpeg_metadata['creation_time'] = dt.isoformat()
    
    # Set GPS data
    if 'geoData' in metadata:
        geo = metadata['geoData']
        lat, lon = geo.get('latitude'), geo.get('longitude')
        if lat is not None and lon is not None:
            ffmpeg_metadata['location'] = f"{lat:+.6f}{lon:+.6f}/"
    
    # Apply metadata using ffmpeg
    input_stream = ffmpeg.input(str(video_path))
    output_stream = ffmpeg.output(
        input_stream, 
        str(output_path),
        **{'c': 'copy', 'metadata': [f"{k}={v}" for k, v in ffmpeg_metadata.items()]}
    )
    ffmpeg.run(output_stream, quiet=True, overwrite_output=True)
```

## Usage Guide

### Prerequisites

1. **Python 3.8+** with pip
2. **ffmpeg** for video processing: `brew install ffmpeg`
3. **immich-go** for upload: Download from [immich-go releases](https://github.com/immich-app/immich-go/releases)

### Installation

```bash
# Navigate to project directory
cd /Users/nitinsrivastava/Documents/home-server

# Install Python dependencies
pip install -r requirements-takeout.txt

# Make script executable
chmod +x scripts/services/enhanced_takeout_import.sh
```

### Basic Usage

#### Process Only (No Upload)

```bash
./scripts/services/enhanced_takeout_import.sh \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir ./tmp/takeout-processed \
    --skip-upload
```

#### Process and Upload to Immich

```bash
# Set environment variables
export IMMICH_SERVER="http://localhost:2283"
export IMMICH_API_KEY="your-api-key-here"

# Run with upload
./scripts/services/enhanced_takeout_import.sh \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir ./tmp/takeout-processed
```

#### Custom Configuration

```bash
./scripts/services/enhanced_takeout_import.sh \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir /path/to/custom/output \
    --immich-server http://your-immich-server:2283 \
    --api-key your-api-key \
    --skip-deps  # Skip dependency installation
```

### Python Script Direct Usage

```bash
python3 scripts/services/enhanced_takeout_import.py \
    --takeout-dir /Volumes/faststore/takeout-downloads \
    --output-dir ./tmp/takeout-processed \
    --immich-server http://localhost:2283 \
    --api-key your-api-key
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--takeout-dir`, `-i` | Directory containing takeout zip files | `/Volumes/faststore/takeout-downloads` |
| `--output-dir`, `-o` | Output directory for processed files | `./tmp/takeout-processed` |
| `--immich-server`, `-s` | Immich server URL | From `IMMICH_SERVER` env var |
| `--api-key`, `-k` | Immich API key | From `IMMICH_API_KEY` env var |
| `--skip-upload` | Skip upload to Immich | false |
| `--skip-deps` | Skip dependency installation | false |

## Metadata Mapping

### Image Files (JPEG, PNG, HEIC, etc.)

| Google Photos JSON | EXIF Tag | EXIF ID | Description |
|-------------------|----------|---------|-------------|
| `photoTakenTime.timestamp` | `DateTimeOriginal` | 36867 | Original photo timestamp |
| `photoTakenTime.timestamp` | `DateTimeDigitized` | 36868 | Digitized timestamp |
| `photoTakenTime.timestamp` | `DateTime` | 306 | File modification time |
| `geoData.latitude` | `GPSLatitude` | GPS IFD | GPS latitude coordinates |
| `geoData.longitude` | `GPSLongitude` | GPS IFD | GPS longitude coordinates |
| `geoData.altitude` | `GPSAltitude` | GPS IFD | GPS altitude |
| `description` | `ImageDescription` | 270 | Image description/caption |
| `googlePhotosOrigin.mobileUpload.deviceType` | `Make` | 271 | Camera make (device type) |

### Video Files (MP4, MOV, AVI, etc.)

| Google Photos JSON | Video Metadata | Description |
|-------------------|----------------|-------------|
| `photoTakenTime.timestamp` | `creation_time` | Video creation timestamp |
| `title` | `title` | Video title |
| `description` | `comment` | Video description |
| `geoData.latitude`, `geoData.longitude` | `location` | GPS coordinates |

### Album Structure

| Google Photos | Immich | Description |
|---------------|--------|-------------|
| Album folder name | Album name | Preserved as-is |
| `metadata.json` → `title` | Album title | Used if different from folder name |
| `metadata.json` → `description` | Album description | Applied to album |

## Processing Statistics

The script provides detailed statistics upon completion:

```
[SUCCESS] Processing complete!
Statistics:
  Total files processed: 15,847
  Images processed: 14,203
  Videos processed: 1,644
  Albums created: 127
  Files skipped: 245
  Errors: 12
```

## Troubleshooting

### Common Issues

#### 1. Space Requirements

**Issue**: Not enough disk space for processing.

**Solution**: The script requires approximately 2-3x the size of your takeout data for temporary files.

```bash
# Check available space
df -h /path/to/output/directory

# Estimate takeout size
du -sh /Volumes/faststore/takeout-downloads
```

#### 2. Missing Dependencies

**Issue**: Python packages or system tools not found.

**Solution**: Install all dependencies:

```bash
# Install Python packages
pip install -r requirements-takeout.txt

# Install system dependencies (macOS)
brew install ffmpeg

# Install immich-go
# Download from: https://github.com/immich-app/immich-go/releases
```

#### 3. EXIF Processing Errors

**Issue**: Images fail to process with EXIF errors.

**Solution**: The script includes fallback mechanisms that copy files even if EXIF processing fails.

```python
# Fallback mechanism in process_image_metadata
except Exception as e:
    logger.error(f"Failed to process image metadata for {image_path}: {e}")
    # Fallback: just copy the file
    shutil.copy2(image_path, output_path)
    return False
```

#### 4. Immich Upload Failures

**Issue**: Upload to Immich fails or times out.

**Solution**: 
1. Verify Immich server is accessible
2. Check API key validity
3. Use manual upload as fallback

```bash
# Manual upload using immich-go
immich-go upload \
    --server http://localhost:2283 \
    --api-key your-api-key \
    --album-from-folder \
    /path/to/processed/files
```

#### 5. Large Archive Processing

**Issue**: Processing 84+ zip files takes too long or runs out of memory.

**Solution**: Process in batches:

```bash
# Process first 20 files
mkdir /tmp/batch1
mv /Volumes/faststore/takeout-downloads/takeout-*-00[1-9].zip /tmp/batch1/
mv /Volumes/faststore/takeout-downloads/takeout-*-01[0-9].zip /tmp/batch1/
mv /Volumes/faststore/takeout-downloads/takeout-*-020.zip /tmp/batch1/

./scripts/services/enhanced_takeout_import.sh --takeout-dir /tmp/batch1
```

### Log Analysis

The script creates detailed logs in `takeout_import.log`:

```bash
# Monitor processing in real-time
tail -f takeout_import.log

# Search for errors
grep ERROR takeout_import.log

# Count processed files by type
grep "processed_images\|processed_videos" takeout_import.log
```

### Performance Optimization

For large datasets (84 zip files with ~15K+ photos):

1. **Use SSD storage** for temporary files
2. **Increase available RAM** (8GB+ recommended)
3. **Process during off-peak hours** for Immich server
4. **Use wired network connection** for uploads

### Validation

After processing, validate the import:

```bash
# Check processed file count
find /path/to/output/processed -type f \( -name "*.jpg" -o -name "*.mp4" \) | wc -l

# Verify EXIF data preservation
exiftool /path/to/processed/file.jpg | grep -E "GPS|Date"

# Check Immich for albums and metadata
# Access Immich web interface and verify albums are created with proper timestamps and GPS data
```

## Advanced Usage

### Custom Metadata Processing

To extend metadata processing for additional fields:

```python
# Add to process_image_metadata method
if 'customField' in metadata:
    exif_dict['0th'][piexif.ImageIFD.Software] = metadata['customField'].encode()
```

### Batch Processing Multiple Users

```bash
#!/bin/bash
for user_dir in /Volumes/faststore/users/*/takeout-downloads; do
    user=$(basename $(dirname $user_dir))
    echo "Processing user: $user"
    
    ./scripts/services/enhanced_takeout_import.sh \
        --takeout-dir "$user_dir" \
        --output-dir "./tmp/$user-processed" \
        --skip-upload
done
```

### Integration with Existing Workflows

The enhanced import can be integrated with existing home server automation:

```bash
# Add to existing media processing pipeline
./scripts/services/enhanced_takeout_import.sh && \
./scripts/media/process_collection.sh && \
./scripts/core/health_check.sh
```

---

## Summary

This enhanced Google Photos takeout import solution provides comprehensive metadata preservation and seamless Immich integration. The solution handles the complete processing pipeline from extraction through upload, maintaining data integrity and providing robust error handling for large-scale imports.

Key benefits:
- **Complete metadata preservation** including GPS, timestamps, and descriptions
- **Scalable processing** for large takeout datasets (84+ zip files)
- **Robust error handling** with detailed logging and fallback mechanisms
- **Flexible deployment** with both shell and Python interfaces
- **Immich integration** with album structure preservation

For support or additional features, refer to the troubleshooting section or extend the processing scripts as needed.

