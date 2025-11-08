#!/usr/bin/env python3
"""
Enhanced Google Photos Takeout Import Script for Immich
Processes Google Photos takeout data with full metadata preservation.

Usage: python3 enhanced_takeout_import.py [options]
"""

import os
import sys
import json
import zipfile
import shutil
import tempfile
import argparse
import subprocess
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import piexif
from PIL import Image, ExifTags
from PIL.ExifTags import TAGS, GPSTAGS
import ffmpeg

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('takeout_import.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class TakeoutProcessor:
    """Processes Google Photos takeout data for Immich import."""
    
    def __init__(self, takeout_dir: str, output_dir: str, immich_server: str = None, api_key: str = None):
        self.takeout_dir = Path(takeout_dir)
        self.output_dir = Path(output_dir)
        self.immich_server = immich_server
        self.api_key = api_key
        self.stats = {
            'total_files': 0,
            'processed_images': 0,
            'processed_videos': 0,
            'skipped_files': 0,
            'errors': 0,
            'albums_created': 0
        }
        
        # Supported file types
        self.image_extensions = {'.jpg', '.jpeg', '.png', '.heic', '.webp', '.tiff', '.bmp'}
        self.video_extensions = {'.mp4', '.mov', '.avi', '.mkv', '.m4v', '.3gp', '.webm'}
        
        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
    def extract_archives(self) -> None:
        """Extract all takeout zip files to a temporary directory."""
        logger.info("Extracting takeout archives...")
        
        # Find all zip files
        zip_files = list(self.takeout_dir.glob("takeout-*.zip"))
        if not zip_files:
            raise ValueError(f"No takeout zip files found in {self.takeout_dir}")
            
        logger.info(f"Found {len(zip_files)} zip files to extract")
        
        # Create extraction directory
        self.extraction_dir = self.output_dir / "extracted"
        self.extraction_dir.mkdir(exist_ok=True)
        
        for zip_file in zip_files:
            logger.info(f"Extracting {zip_file.name}...")
            try:
                with zipfile.ZipFile(zip_file, 'r') as zip_ref:
                    zip_ref.extractall(self.extraction_dir)
            except Exception as e:
                logger.error(f"Failed to extract {zip_file}: {e}")
                self.stats['errors'] += 1
                
        # Find the Google Photos directory
        self.photos_dir = self.extraction_dir / "Takeout" / "Google Photos"
        if not self.photos_dir.exists():
            raise ValueError(f"Google Photos directory not found in extracted data")
            
        logger.info(f"Extraction complete. Photos directory: {self.photos_dir}")
    
    def parse_metadata(self, json_path: Path) -> Dict:
        """Parse metadata from Google Photos JSON file."""
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse metadata from {json_path}: {e}")
            return {}
    
    def convert_timestamp_to_exif(self, timestamp: str) -> str:
        """Convert Unix timestamp to EXIF date format."""
        try:
            dt = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
            return dt.strftime('%Y:%m:%d %H:%M:%S')
        except (ValueError, TypeError):
            return ""
    
    def set_gps_exif(self, exif_dict: Dict, latitude: float, longitude: float, altitude: float = None) -> None:
        """Set GPS information in EXIF data."""
        try:
            # Convert decimal degrees to degrees, minutes, seconds
            def decimal_to_dms(decimal_deg):
                degrees = int(abs(decimal_deg))
                minutes_float = (abs(decimal_deg) - degrees) * 60
                minutes = int(minutes_float)
                seconds = (minutes_float - minutes) * 60
                return ((degrees, 1), (minutes, 1), (int(seconds * 100), 100))
            
            gps_ifd = {}
            
            # Latitude
            gps_ifd[piexif.GPSIFD.GPSLatitude] = decimal_to_dms(latitude)
            gps_ifd[piexif.GPSIFD.GPSLatitudeRef] = 'N' if latitude >= 0 else 'S'
            
            # Longitude
            gps_ifd[piexif.GPSIFD.GPSLongitude] = decimal_to_dms(longitude)
            gps_ifd[piexif.GPSIFD.GPSLongitudeRef] = 'E' if longitude >= 0 else 'W'
            
            # Altitude
            if altitude is not None:
                gps_ifd[piexif.GPSIFD.GPSAltitude] = (int(altitude * 100), 100)
                gps_ifd[piexif.GPSIFD.GPSAltitudeRef] = 0  # Above sea level
            
            exif_dict['GPS'] = gps_ifd
            
        except Exception as e:
            logger.error(f"Failed to set GPS EXIF data: {e}")
    
    def process_image_metadata(self, image_path: Path, metadata: Dict, output_path: Path) -> bool:
        """Process and embed metadata into image file."""
        try:
            # Load existing EXIF data
            try:
                exif_dict = piexif.load(str(image_path))
            except Exception:
                # Create new EXIF structure if none exists
                exif_dict = {"0th": {}, "Exif": {}, "GPS": {}, "1st": {}, "thumbnail": None}
            
            # Set timestamp from photoTakenTime
            if 'photoTakenTime' in metadata:
                timestamp = metadata['photoTakenTime'].get('timestamp')
                if timestamp:
                    exif_time = self.convert_timestamp_to_exif(timestamp)
                    if exif_time:
                        exif_dict['Exif'][piexif.ExifIFD.DateTimeOriginal] = exif_time.encode()
                        exif_dict['Exif'][piexif.ExifIFD.DateTimeDigitized] = exif_time.encode()
                        exif_dict['0th'][piexif.ImageIFD.DateTime] = exif_time.encode()
            
            # Set GPS data
            if 'geoData' in metadata:
                geo = metadata['geoData']
                lat = geo.get('latitude')
                lon = geo.get('longitude')
                alt = geo.get('altitude')
                if lat is not None and lon is not None:
                    self.set_gps_exif(exif_dict, lat, lon, alt)
            
            # Set image description
            if 'description' in metadata and metadata['description']:
                exif_dict['0th'][piexif.ImageIFD.ImageDescription] = metadata['description'].encode()
            
            # Set camera make/model if available
            if 'googlePhotosOrigin' in metadata:
                origin = metadata['googlePhotosOrigin']
                if 'mobileUpload' in origin:
                    device_type = origin['mobileUpload'].get('deviceType', '')
                    if device_type:
                        exif_dict['0th'][piexif.ImageIFD.Make] = f"Google Photos ({device_type})".encode()
            
            # Copy image with new EXIF data
            shutil.copy2(image_path, output_path)
            
            # Save EXIF data
            exif_bytes = piexif.dump(exif_dict)
            piexif.insert(exif_bytes, str(output_path))
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to process image metadata for {image_path}: {e}")
            # Fallback: just copy the file
            shutil.copy2(image_path, output_path)
            return False
    
    def process_video_metadata(self, video_path: Path, metadata: Dict, output_path: Path) -> bool:
        """Process and embed metadata into video file using ffmpeg."""
        try:
            # Copy video file first
            shutil.copy2(video_path, output_path)
            
            # Prepare metadata for ffmpeg
            ffmpeg_metadata = {}
            
            # Set creation time
            if 'photoTakenTime' in metadata:
                timestamp = metadata['photoTakenTime'].get('timestamp')
                if timestamp:
                    dt = datetime.fromtimestamp(int(timestamp), tz=timezone.utc)
                    ffmpeg_metadata['creation_time'] = dt.isoformat()
            
            # Set title and description
            if 'title' in metadata and metadata['title']:
                ffmpeg_metadata['title'] = metadata['title']
            
            if 'description' in metadata and metadata['description']:
                ffmpeg_metadata['comment'] = metadata['description']
            
            # Set GPS data in metadata
            if 'geoData' in metadata:
                geo = metadata['geoData']
                lat = geo.get('latitude')
                lon = geo.get('longitude')
                if lat is not None and lon is not None:
                    ffmpeg_metadata['location'] = f"{lat:+.6f}{lon:+.6f}/"
                    ffmpeg_metadata['location-eng'] = f"{lat:+.6f}{lon:+.6f}/"
            
            # Apply metadata if any exists
            if ffmpeg_metadata:
                # Create temporary file for metadata update
                temp_output = output_path.with_suffix(f".temp{output_path.suffix}")
                
                input_stream = ffmpeg.input(str(output_path))
                output_stream = ffmpeg.output(
                    input_stream, 
                    str(temp_output),
                    **{'c': 'copy', 'map_metadata': '0', 'metadata': [f"{k}={v}" for k, v in ffmpeg_metadata.items()]}
                )
                
                ffmpeg.run(output_stream, quiet=True, overwrite_output=True)
                
                # Replace original with updated file
                temp_output.replace(output_path)
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to process video metadata for {video_path}: {e}")
            # Fallback: just copy the file
            if not output_path.exists():
                shutil.copy2(video_path, output_path)
            return False
    
    def process_album(self, album_dir: Path) -> None:
        """Process a single album directory."""
        album_name = album_dir.name
        logger.info(f"Processing album: {album_name}")
        
        # Create output album directory
        output_album_dir = self.output_dir / "processed" / album_name
        output_album_dir.mkdir(parents=True, exist_ok=True)
        
        # Parse album metadata if available
        album_metadata = {}
        album_metadata_file = album_dir / "metadata.json"
        if album_metadata_file.exists():
            album_metadata = self.parse_metadata(album_metadata_file)
            logger.info(f"Found album metadata: {album_metadata.get('title', album_name)}")
        
        # Process all media files in the album
        for file_path in album_dir.iterdir():
            if file_path.is_file() and not file_path.name.endswith('.json'):
                self.process_media_file(file_path, output_album_dir)
        
        self.stats['albums_created'] += 1
    
    def process_media_file(self, file_path: Path, output_dir: Path) -> None:
        """Process a single media file with its metadata."""
        self.stats['total_files'] += 1
        
        # Skip if not a supported media file
        if file_path.suffix.lower() not in (self.image_extensions | self.video_extensions):
            self.stats['skipped_files'] += 1
            return
        
        # Look for metadata file
        metadata_file = file_path.with_suffix(file_path.suffix + '.supplemental-metadata.json')
        if not metadata_file.exists():
            # Try alternative naming
            metadata_file = file_path.parent / f"{file_path.name}.json"
        
        metadata = {}
        if metadata_file.exists():
            metadata = self.parse_metadata(metadata_file)
        else:
            logger.warning(f"No metadata found for {file_path}")
        
        # Create output file path
        output_file = output_dir / file_path.name
        
        # Process based on file type
        success = False
        if file_path.suffix.lower() in self.image_extensions:
            success = self.process_image_metadata(file_path, metadata, output_file)
            if success:
                self.stats['processed_images'] += 1
        elif file_path.suffix.lower() in self.video_extensions:
            success = self.process_video_metadata(file_path, metadata, output_file)
            if success:
                self.stats['processed_videos'] += 1
        
        if not success:
            self.stats['errors'] += 1
    
    def upload_to_immich(self) -> None:
        """Upload processed files to Immich using immich-go."""
        if not self.immich_server or not self.api_key:
            logger.warning("Immich server or API key not provided. Skipping upload.")
            return
        
        processed_dir = self.output_dir / "processed"
        if not processed_dir.exists():
            logger.error("No processed files found for upload")
            return
        
        logger.info("Uploading to Immich...")
        
        try:
            # Check if immich-go is available
            subprocess.run(['immich-go', '--version'], check=True, capture_output=True)
        except (subprocess.CalledProcessError, FileNotFoundError):
            logger.error("immich-go not found. Please install from https://github.com/immich-app/immich-go")
            return
        
        # Upload each album separately to maintain structure
        for album_dir in processed_dir.iterdir():
            if album_dir.is_dir():
                logger.info(f"Uploading album: {album_dir.name}")
                try:
                    cmd = [
                        'immich-go',
                        'upload',
                        '--server', self.immich_server,
                        '--api-key', self.api_key,
                        '--album', album_dir.name,
                        str(album_dir)
                    ]
                    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
                    logger.info(f"Successfully uploaded {album_dir.name}")
                except subprocess.CalledProcessError as e:
                    logger.error(f"Failed to upload {album_dir.name}: {e.stderr}")
                    self.stats['errors'] += 1
    
    def process_all(self) -> None:
        """Process all takeout data."""
        logger.info("Starting Google Photos takeout processing...")
        
        # Extract archives
        self.extract_archives()
        
        # Process each album directory
        for album_dir in self.photos_dir.iterdir():
            if album_dir.is_dir() and not album_dir.name.startswith('.'):
                self.process_album(album_dir)
        
        # Upload to Immich if configured
        self.upload_to_immich()
        
        # Print statistics
        self.print_stats()
    
    def print_stats(self) -> None:
        """Print processing statistics."""
        logger.info("Processing complete!")
        logger.info(f"Statistics:")
        logger.info(f"  Total files processed: {self.stats['total_files']}")
        logger.info(f"  Images processed: {self.stats['processed_images']}")
        logger.info(f"  Videos processed: {self.stats['processed_videos']}")
        logger.info(f"  Albums created: {self.stats['albums_created']}")
        logger.info(f"  Files skipped: {self.stats['skipped_files']}")
        logger.info(f"  Errors: {self.stats['errors']}")

def main():
    parser = argparse.ArgumentParser(description='Enhanced Google Photos Takeout Import for Immich')
    parser.add_argument('--takeout-dir', '-i', required=True,
                      help='Directory containing takeout zip files')
    parser.add_argument('--output-dir', '-o', required=True,
                      help='Output directory for processed files')
    parser.add_argument('--immich-server', '-s',
                      help='Immich server URL (e.g., http://localhost:2283)')
    parser.add_argument('--api-key', '-k',
                      help='Immich API key')
    parser.add_argument('--skip-upload', action='store_true',
                      help='Skip upload to Immich (only process files)')
    
    args = parser.parse_args()
    
    # Override upload settings if skip-upload is specified
    if args.skip_upload:
        args.immich_server = None
        args.api_key = None
    
    processor = TakeoutProcessor(
        takeout_dir=args.takeout_dir,
        output_dir=args.output_dir,
        immich_server=args.immich_server,
        api_key=args.api_key
    )
    
    try:
        processor.process_all()
    except KeyboardInterrupt:
        logger.info("Processing interrupted by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Processing failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()

