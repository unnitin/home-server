# ⚙️ Environment Variables Guide

This project uses environment variables to control **storage**, **services**, and **automation** behavior. Export them in your shell or create a `.env.local` file and `source` it before running scripts.

> 💡 **Tip**: Only set what you need — sensible defaults exist for most values.

## 📋 Quick Reference

### 🔴 Required Variables

| Variable | Location | Description |
|----------|----------|-------------|
| `IMMICH_DB_PASSWORD` | `services/immich/.env` | **Database password for Immich (Postgres)** - Must be set! |

### 🟡 Storage Variables (For RAID Setup)

| Variable | Default | Example | Description |
|----------|---------|---------|-------------|
| `RAID_I_UNDERSTAND_DATA_LOSS` | *(unset)* | `1` | **Safety gate** - Must be `1` to allow destructive rebuilds |
| `SSD_DISKS` | *(unset)* | `"disk4 disk5"` | Space-separated **disk identifiers** for SSD array (warmstore) |
| `NVME_DISKS` | *(unset)* | `"disk2 disk3"` | Disk identifiers for NVMe array (faststore) |
| `COLD_DISKS` | *(unset)* | `"disk6 disk7"` | Disk identifiers for HDD array (coldstore) |

### 🟢 Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMMICH_SERVER` | *(unset)* | Server URL for Takeout import (e.g., `http://localhost:2283`) |
| `IMMICH_API_KEY` | *(unset)* | API key for Takeout import (create in Immich settings) |

---

## 📖 Detailed Configuration

### 🔴 Required: Immich Database

**File**: `services/immich/.env`

```bash
# Copy the example and edit
cd services/immich
cp .env.example .env
${EDITOR:-nano} .env
```

**Required setting**:
```bash
IMMICH_DB_PASSWORD=your_secure_password_here
```

> ⚠️ **Important**: Choose a strong password. This protects your photo database.

---

### 💾 Storage Configuration

#### Disk Identification

First, identify your disks:
```bash
diskutil list
```

Look for output like:
```
/dev/disk0 (internal, physical):
/dev/disk1 (internal, physical):
/dev/disk2 (external, physical):   <-- Use "disk2" (whole disk)
   #:  TYPE NAME       SIZE       IDENTIFIER
   0:  GUID_partition_scheme        *1.0 TB    disk2
   1:  Apple_APFS Container disk2   1.0 TB     disk2s1  <-- Don't use "disk2s1"
```

> 💡 **Use whole disk IDs** (like `disk4`), **not partition slices** (like `disk4s1`).

#### Storage Array Configuration

```bash
# Safety gate - REQUIRED for any RAID operations
export RAID_I_UNDERSTAND_DATA_LOSS=1

# SSD Array (warmstore) - for Plex media at /Volumes/Media
export SSD_DISKS="disk4 disk5"              # 2 disks = mirror
export SSD_DISKS="disk4 disk5 disk6 disk7"  # 4 disks = RAID10

# NVMe Array (faststore) - for Immich photos at /Volumes/Photos  
export NVME_DISKS="disk2 disk3"             # 2 disks = mirror
export NVME_DISKS="disk2 disk3 disk8 disk9" # 4 disks = RAID10

# HDD Array (coldstore) - for archive at /Volumes/Archive
export COLD_DISKS="disk6"                   # Single disk
export COLD_DISKS="disk6 disk7"             # 2 disks = mirror
```

#### Array Names and Mount Points

| Array Name | Default Mount | Purpose | Disk Variable |
|------------|---------------|---------|---------------|
| `faststore` | `/Volumes/Photos` | Immich photos (high-speed) | `NVME_DISKS` |
| `warmstore` | `/Volumes/Media` | Plex media (good speed) | `SSD_DISKS` |
| `coldstore` | `/Volumes/Archive` | Archive storage (capacity) | `COLD_DISKS` |

**Custom names/mounts** *(advanced)*:
```bash
export SSD_RAID_NAME="my_media_array"
export NVME_RAID_NAME="my_photo_array"  
export COLD_RAID_NAME="my_archive_array"

export MEDIA_MOUNT="/Volumes/MyMedia"
export PHOTOS_MOUNT="/Volumes/MyPhotos"
export ARCHIVE_MOUNT="/Volumes/MyArchive"
```

---

### 📸 Immich Integration

For [Google Takeout import](IMMICH.md#google-takeout-import):

```bash
# Immich server URL (local)
export IMMICH_SERVER=http://localhost:2283

# API key (create in Immich → Account → API Keys)
export IMMICH_API_KEY=your_api_key_here
```

**Setup API key**:
1. Open Immich web UI: http://localhost:2283
2. Go to Account (profile icon) → API Keys
3. Create new API key
4. Copy and export it as `IMMICH_API_KEY`

---

### 🔒 Tailscale Configuration

Tailscale doesn't require environment variables - it's configured interactively:

```bash
# Connect to your Tailscale network
sudo tailscale up --accept-dns=true

# Optional: Advanced flags
sudo tailscale up --accept-dns=true --advertise-exit-node --ssh
```

**HTTPS serving** (after setup):
```bash
# Direct service access
sudo tailscale serve --https=443   http://localhost:2283    # Immich
sudo tailscale serve --https=32400 http://localhost:32400   # Plex

# With reverse proxy (replaces direct Immich access)
sudo tailscale serve --https=443   http://localhost:8443    # Caddy proxy
```

---

## 🛠️ Advanced Configuration

### Storage Expansion Options

```bash
# Pre-clean existing RAID sets (DESTRUCTIVE!)
export CLEAN_BEFORE_RAID=1
export RAID_I_UNDERSTAND_DATA_LOSS=1
```

### Backup Configuration

No environment variables needed - use explicit paths:
```bash
# Backup warmstore to external drive
./scripts/14_backup_store.sh warmstore /Volumes/MyBackup/MediaBackup

# Restore from backup  
./scripts/15_restore_store.sh /Volumes/MyBackup/MediaBackup warmstore
```

---

## 📝 Configuration Examples

### Example 1: Minimal Setup (No RAID)
```bash
# services/immich/.env
IMMICH_DB_PASSWORD=my_secure_password123
```

**Result**: Immich uses existing storage, no RAID arrays created.

### Example 2: Photo Storage Only (NVMe RAID)
```bash
# Environment
export RAID_I_UNDERSTAND_DATA_LOSS=1
export NVME_DISKS="disk2 disk3"

# services/immich/.env  
IMMICH_DB_PASSWORD=my_secure_password123
```

**Result**: 2-disk NVMe mirror at `/Volumes/Photos` for Immich.

### Example 3: Full Media Server (SSD + NVMe RAID)
```bash
# Environment
export RAID_I_UNDERSTAND_DATA_LOSS=1
export SSD_DISKS="disk4 disk5 disk6 disk7"     # 4-disk RAID10
export NVME_DISKS="disk2 disk3"                # 2-disk mirror

# services/immich/.env
IMMICH_DB_PASSWORD=my_secure_password123

# Takeout import
export IMMICH_SERVER=http://localhost:2283
export IMMICH_API_KEY=abcd1234-your-api-key
```

**Result**: 
- `/Volumes/Photos` (NVMe mirror) for Immich
- `/Volumes/Media` (SSD RAID10) for Plex  
- Google Takeout import ready

### Example 4: Complete Setup with Archive
```bash
# Environment  
export RAID_I_UNDERSTAND_DATA_LOSS=1
export SSD_DISKS="disk4 disk5"                 # Media mirror
export NVME_DISKS="disk2 disk3"                # Photo mirror  
export COLD_DISKS="disk6"                      # Archive single disk

# services/immich/.env
IMMICH_DB_PASSWORD=my_secure_password123
```

**Result**: Three-tier storage with photos, media, and archive.

---

## ⚠️ Safety Notes

### RAID Operations
- **DESTRUCTIVE**: Rebuilds delete existing data
- **Backup first**: Use `./scripts/14_backup_store.sh`
- **Safety gate**: `RAID_I_UNDERSTAND_DATA_LOSS=1` required
- **Re-runnable**: Scripts delete and recreate existing arrays

### Disk Selection
- **Whole disks only**: Use `disk4`, not `disk4s1`
- **Verify with**: `diskutil list` before setting variables
- **External drives**: Can be used but may have different identifiers

### Network Security
- **Tailscale only**: No direct internet exposure
- **HTTPS encryption**: All remote connections encrypted
- **API keys**: Keep Immich API keys secure

---

## 🔍 Verification Commands

```bash
# Check current environment
env | grep -E "(RAID|DISK|IMMICH)" | sort

# Verify disk IDs
diskutil list

# Check Immich configuration
cat services/immich/.env

# Test storage mounts
./diagnostics/verify_media_paths.sh

# Check RAID status
./diagnostics/check_raid_status.sh
```

---

**Next Steps**: 
- [📋 Quick Start Guide](QUICKSTART.md) - Get running quickly
- [📖 Detailed Setup](SETUP.md) - Step-by-step instructions  
- [💾 Storage Management](STORAGE.md) - RAID operations and backups
