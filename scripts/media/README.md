# 📁 Media Module

Media layer providing automated file organization, Plex naming conventions, and media processing workflows.

## 📋 Scripts

### **Core Processing**

#### **processor.sh**
**Purpose**: Main orchestrator for processing media files according to Plex naming conventions  
**Usage**: `./scripts/media/processor.sh [--movies-only|--tv-only|--collections-only|--cleanup-only]`  
**Features**: 
- Processes Movies: `Movie Name (Year)/Movie Name (Year).ext`
- Processes TV Shows: `Show Name (Year)/Season XX/Show Name - sXXeYY.ext`  
- Processes Collections: Preserves exact folder structure
- Comprehensive error handling and logging

#### **watcher.sh**
**Purpose**: Monitors Staging directories for new files and triggers automatic processing  
**Usage**: `./scripts/media/watcher.sh {start|stop|status|restart}`  
**Features**: Real-time monitoring, delay for file transfers, lock files, automatic restart

### **File Type Processors**

#### **process_movie.sh**
**Purpose**: Processes individual movie files according to Plex naming standards  
**Usage**: `./scripts/media/process_movie.sh <source_file> <target_dir> <log_file> [rel_path]`  
**Features**: Extracts movie name and year, creates Plex-compliant structure

#### **process_tv_show.sh**
**Purpose**: Processes individual TV show files according to Plex naming standards  
**Usage**: `./scripts/media/process_tv_show.sh <source_file> <target_dir> <log_file> [rel_path]`  
**Features**: Extracts show, season, episode info, handles various naming patterns

#### **process_collection.sh**
**Purpose**: Processes individual collection files while preserving exact folder structure  
**Usage**: `./scripts/media/process_collection.sh <source_file> <target_dir> <log_file> [rel_path]`  
**Features**: Preserves exact structure, maintains original naming

## 🎬 Supported Media Formats

- `.mkv`, `.mp4`, `.avi`, `.mov`, `.m4v`, `.wmv`, `.flv`, `.webm`

## 📁 Processing Workflow

1. **Detection**: `watcher.sh` monitors `/Volumes/warmstore/Staging/`
2. **Classification**: Files sorted by directory (Movies, TV Shows, Collections)
3. **Processing**: Appropriate processor script handles file organization
4. **Validation**: Files moved to target locations with Plex naming
5. **Cleanup**: Empty directories and system files removed
6. **Logging**: All activities logged to `/Volumes/warmstore/logs/media-watcher/`

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`, `services/` (Plex)  
**Used by**: `automation/` (LaunchD)

## 📁 Module Architecture

```
scripts/media/
├── processor.sh          # Main processing orchestrator
├── watcher.sh           # File system monitoring
├── process_movie.sh     # Movie file processing
├── process_tv_show.sh   # TV show processing  
├── process_collection.sh # Collection processing
└── README.md           # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
