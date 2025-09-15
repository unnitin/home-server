# 💾 Storage Management Guide

Comprehensive guide for managing storage arrays, expansion, backups, and optimization on your Mac mini home server.

## 📋 Storage Architecture Overview

### Three-Tier Storage Design

| Tier | Purpose | Technology | Mount Point | Array Name | Status |
|------|---------|------------|-------------|------------|---------|
| **🚀 Faststore** | Photos/high-speed | NVMe RAID | `/Volumes/faststore` | `faststore` | ✅ **Active** |
| **💾 Warmstore** | Media/good-speed | SSD RAID | `/Volumes/warmstore` | `warmstore` | ✅ **Active** |
| **🗄️ Coldstore** | Archive/capacity | HDD RAID | `/Volumes/coldstore` | `coldstore` | 🟡 *Placeholder directory* |

### Current Configuration

**Mount Structure**:
```bash
/Volumes/faststore/          # NVMe RAID array (1.9TB)
├── photos/                  # Immich photos (877MB)
├── metadata/                # Plex metadata (742MB)
├── databases/               # Database storage
└── processing/              # Processing directories

/Volumes/warmstore/          # SSD RAID array (1.9TB)
├── Movies/                  # Plex Movies (219GB)
├── TV Shows/               # Plex TV Shows (246GB)
└── Collections/            # Media collections (109GB)

# Service Access Points:
/Volumes/Photos/             → /Volumes/faststore/photos/     (Immich)
/Volumes/Media/              → /Volumes/warmstore/            (Plex)
/Volumes/Archive/            → /Volumes/coldstore/            (Future)
```

**Setup Scripts**: Use the provided scripts for proper setup:
```bash
# Mount RAID arrays at correct locations
./scripts/storage/format_and_mount.sh

# Create service access symlinks
./scripts/storage/setup_service_symlinks.sh
```

### RAID Configurations
- **2 disks**: Mirror (RAID1) - 50% capacity, 1-disk fault tolerance
- **4 disks**: RAID10 - 50% capacity, 2-disk fault tolerance
- **Single disk**: JBOD - 100% capacity, no fault tolerance

---

## 🔧 Initial Storage Setup

### Disk Identification
```bash
# List all disks
diskutil list

# Identify disk types and sizes
system_profiler SPSerialATADataType
system_profiler SPNVMeDataType
```

**Example output interpretation**:
```
/dev/disk2 (external, physical):    <-- Use "disk2"
   #:  TYPE NAME       SIZE       IDENTIFIER
   0:  GUID_partition_scheme        *1.0 TB    disk2
   1:  Apple_APFS Container disk2   1.0 TB     disk2s1    <-- Don't use slices
```

### Environment Configuration
```bash
# Required safety gate
export RAID_I_UNDERSTAND_DATA_LOSS=1

# Example configurations
export SSD_DISKS="disk4 disk5"          # 2-disk SSD mirror
export NVME_DISKS="disk2 disk3"         # 2-disk NVMe mirror
export COLD_DISKS="disk6"               # Single HDD

# For 4-disk arrays
export SSD_DISKS="disk4 disk5 disk6 disk7"    # 4-disk RAID10
```

### Creating Arrays

**Automated approach**:
```bash
# Create and format all configured arrays
./scripts/09_rebuild_storage.sh warmstore faststore coldstore
./scripts/12_format_and_mount_raids.sh
```

**Step-by-step approach**:
```bash
# Create individual arrays
./scripts/10_create_raid10_ssd.sh       # SSD warmstore
./scripts/11_create_raid10_nvme.sh      # NVMe faststore
./scripts/13_create_raid_coldstore.sh   # HDD coldstore

# Format and mount
./scripts/12_format_and_mount_raids.sh
```

---

## 📈 Scaling Storage

### Planning Expansion

**Growth scenarios**:
1. **Add new tier**: Add coldstore to existing setup
2. **Expand tier**: 2 disks → 4 disks (rebuild required)
3. **Replace tier**: Upgrade to larger/faster disks

### Expansion Process (2 → 4 Disks)

> ⚠️ **DESTRUCTIVE PROCESS** - Requires backup and restore

**1. Backup existing data**:
```bash
# Backup warmstore to external drive
rsync -av --progress /Volumes/Media/ /Volumes/Backup/MediaBackup/

# Verify backup
ls -la /Volumes/Backup/MediaBackup/
```

**2. Update environment**:
```bash
export RAID_I_UNDERSTAND_DATA_LOSS=1
export SSD_DISKS="disk4 disk5 disk6 disk7"  # Add new disks
```

**3. Rebuild array**:
```bash
# This destroys the existing 2-disk array
./scripts/09_rebuild_storage.sh warmstore
./scripts/12_format_and_mount_raids.sh
```

**4. Restore data**:
```bash
# Restore from backup using rsync
rsync -av --progress /Volumes/Backup/MediaBackup/ /Volumes/Media/
```

**5. Verify**:
```bash
./diagnostics/check_raid_status.sh
./diagnostics/verify_media_paths.sh
```

### Adding New Storage Tier

**Example: Adding coldstore**:
```bash
# Configure new disks
export RAID_I_UNDERSTAND_DATA_LOSS=1
export COLD_DISKS="disk8 disk9"

# Create new array (doesn't affect existing)
./scripts/13_create_raid_coldstore.sh
./scripts/12_format_and_mount_raids.sh
```

---

## 🔄 Backup & Restore

### Backup Procedures

**External drive backup**:
```bash
# Backup specific array
rsync -av --progress /Volumes/Media/ /Volumes/MyBackup/MediaBackup/
rsync -av --progress /Volumes/Photos/ /Volumes/MyBackup/PhotoBackup/

# Check backup progress (dry run first)
rsync --dry-run -av /Volumes/Media/ /Volumes/MyBackup/MediaBackup/
```

**What gets backed up**:
- All files and directory structure
- Preserves timestamps and permissions
- Uses rsync for incremental backups
- Excludes temporary and system files

**Backup verification**:
```bash
# Compare source and backup
diff -r /Volumes/Media/ /Volumes/MyBackup/MediaBackup/

# Check backup size
du -sh /Volumes/MyBackup/*
```

### Restore Procedures

**Restore from backup**:
```bash
# Restore specific array (dry run first - recommended)
rsync --dry-run -av /Volumes/MyBackup/MediaBackup/ /Volumes/Media/

# Actual restore
rsync -av --progress /Volumes/MyBackup/MediaBackup/ /Volumes/Media/
```

**Selective restore**:
```bash
# Restore specific folders
rsync -av /Volumes/MyBackup/MediaBackup/Movies/ /Volumes/Media/Movies/
rsync -av /Volumes/MyBackup/PhotoBackup/2023/ /Volumes/Photos/2023/
```

### Automated Backup Scripts

**Weekly backup script** (`backup_weekly.sh`):
```bash
#!/bin/bash
BACKUP_ROOT="/Volumes/Backup"
DATE=$(date +%Y%m%d)

# Backup each tier using rsync
rsync -av --progress /Volumes/Media/ "$BACKUP_ROOT/Media_$DATE/"
rsync -av --progress /Volumes/Photos/ "$BACKUP_ROOT/Photos_$DATE/"

# Cleanup old backups (keep 4 weeks)
find "$BACKUP_ROOT" -name "Media_*" -mtime +28 -exec rm -rf {} \;
find "$BACKUP_ROOT" -name "Photos_*" -mtime +28 -exec rm -rf {} \;
```

---

## 🔍 Monitoring & Health

### RAID Health Checks
```bash
# Comprehensive RAID status
./diagnostics/check_raid_status.sh

# Manual checks
diskutil appleRAID list
diskutil info /dev/disk5
```

**Healthy output example**:
```
AppleRAID sets (1 found)
================================================================================
Name:                 warmstore
Unique ID:            12345678-1234-1234-1234-123456789ABC
Type:                 Mirror
Status:               Online
Size:                 1.0 TB (1000204886016 Bytes)
Rebuild:              manual
Device Node:          /dev/disk5
```

### Storage Usage Monitoring
```bash
# Quick overview
./diagnostics/verify_media_paths.sh

# Detailed usage
df -h /Volumes/*
du -sh /Volumes/Media/*
du -sh /Volumes/Photos/*
```

### Performance Testing
```bash
# Write speed test
dd if=/dev/zero of=/Volumes/Photos/test_file bs=1m count=1000
rm /Volumes/Photos/test_file

# Read speed test
dd if=/Volumes/Photos/large_file of=/dev/null bs=1m
```

### Disk Health
```bash
# Check individual disk health
diskutil info disk4 | grep -E "(SMART|Error)"

# For more detailed SMART data (requires smartctl)
# brew install smartmontools
# sudo smartctl -a /dev/disk4
```

---

## ⚠️ Troubleshooting Storage Issues

### Array Won't Mount

**Check array status**:
```bash
diskutil appleRAID list
diskutil list
```

**Common fixes**:
```bash
# Force mount
sudo diskutil mount /dev/disk5

# Repair filesystem
sudo diskutil verifyVolume /Volumes/Media
sudo diskutil repairVolume /Volumes/Media
```

### Degraded Array

**Identify failed disk**:
```bash
diskutil appleRAID list
# Look for "Degraded" status or missing members
```

**Replace failed disk**:
```bash
# Note: This is a simplified example
# 1. Identify replacement disk
# 2. Add to array (if supported)
# 3. Or rebuild entire array with backup/restore
```

### Performance Issues

**Slow array performance**:
1. **Check individual disks**: One slow disk affects entire array
2. **Verify connections**: USB 3.0 vs Thunderbolt vs internal
3. **Check system load**: High CPU/memory usage affects I/O
4. **Consider array type**: Mirror vs RAID10 performance differences

**Optimization tips**:
- Use fastest disks in most active tier (faststore)
- Ensure good cooling for external drives
- Use quality cables and enclosures
- Monitor for thermal throttling

### Data Recovery

**Partial data loss**:
```bash
# Use backup to restore missing files
rsync -av --existing /Volumes/Backup/MediaBackup/ /Volumes/Media/

# Find and restore specific files
find /Volumes/Backup -name "missing_file.mkv" -exec cp {} /Volumes/Media/ \;
```

**Complete array failure**:
1. **Don't panic**: Data may still be recoverable
2. **Stop using the array**: Prevent further damage
3. **Professional recovery**: Consider data recovery services for critical data
4. **Restore from backup**: Use latest backup if available

---

## 🔄 Maintenance Procedures

### Regular Maintenance (Weekly)

```bash
# Check array health
./diagnostics/check_raid_status.sh

# Monitor disk usage
df -h /Volumes/*

# Verify mounts
./diagnostics/verify_media_paths.sh
```

### Monthly Maintenance

```bash
# Full backup verification (dry run)
rsync --dry-run -av /Volumes/Media/ /tmp/backup_test/

# Disk health check
diskutil verifyVolume /Volumes/Media
diskutil verifyVolume /Volumes/Photos

# Performance test
dd if=/dev/zero of=/Volumes/Media/perf_test bs=1m count=100
rm /Volumes/Media/perf_test
```

### Quarterly Maintenance

```bash
# Complete backup refresh
rsync -av --progress /Volumes/Media/ /Volumes/Backup/MediaBackup_Q$(date +%q)/
rsync -av --progress /Volumes/Photos/ /Volumes/Backup/PhotoBackup_Q$(date +%q)/

# Array rebuild test (if spare disks available)
# Document the process and timing

# Update documentation
# Record any configuration changes
```

---

## 📊 Optimization Strategies

### Performance Optimization

**Tier assignment**:
- **NVMe (faststore)**: Immich photos, active projects
- **SSD (warmstore)**: Plex media, frequently accessed files
- **HDD (coldstore)**: Archives, backups, rarely accessed data

**File organization**:
```bash
# Optimize by access patterns
/Volumes/Photos/          # Current photos (NVMe)
/Volumes/Media/Current/   # Recently added media (SSD)
/Volumes/Media/Archive/   # Older media (consider moving to coldstore)
/Volumes/Archive/         # Long-term storage (HDD)
```

### Capacity Planning

**Monitor growth trends**:
```bash
# Track usage over time
echo "$(date): $(df -h /Volumes/Photos | tail -1)" >> /tmp/storage_growth.log
echo "$(date): $(df -h /Volumes/Media | tail -1)" >> /tmp/storage_growth.log
```

**Expansion triggers**:
- **85% full**: Plan expansion
- **90% full**: Execute expansion soon
- **95% full**: Critical - expand immediately

### Cost Optimization

**Storage tier strategy**:
1. **Start small**: 2-disk mirrors for each tier
2. **Expand when needed**: Upgrade to 4-disk RAID10
3. **Move data down**: Archive old content to cheaper storage

**Hardware choices**:
- **NVMe**: Premium for photos (smaller capacity OK)
- **SSD**: Good balance for media (larger capacity)
- **HDD**: Cheapest per GB for archives (largest capacity)

---

## 🔧 Advanced Configuration

### Custom Array Names

```bash
# Override default names
export SSD_RAID_NAME="media_server"
export NVME_RAID_NAME="photo_vault"
export COLD_RAID_NAME="archive_depot"

# Custom mount points
export MEDIA_MOUNT="/Volumes/MediaServer"
export PHOTOS_MOUNT="/Volumes/PhotoVault"
export ARCHIVE_MOUNT="/Volumes/ArchiveDepot"
```

### Pre-cleaning Disks

**For problem disks**:
```bash
export CLEAN_BEFORE_RAID=1
export RAID_I_UNDERSTAND_DATA_LOSS=1

# This will completely wipe and repartition disks
./scripts/09_preclean_disks_for_raid.sh
./scripts/09_rebuild_storage.sh warmstore
```

### External Drive Integration

**Single external drives**:
```bash
# Use external drive as coldstore without RAID
export COLD_DISKS=""  # Empty to skip RAID creation

# Mount external drive manually
sudo diskutil mount /dev/disk6s1
sudo mkdir -p /Volumes/Archive
sudo mount_apfs /dev/disk6s1 /Volumes/Archive
```

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](QUICKSTART.md)** - Initial storage setup
- **📖 [Detailed Setup Guide](SETUP.md)** - Step-by-step storage configuration
- **⚙️ [Environment Variables](ENVIRONMENT.md)** - Storage configuration reference
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Storage problem solutions
- **📸 [Immich Setup](IMMICH.md)** - Photo storage optimization
- **🎬 [Plex Setup](PLEX.md)** - Media storage optimization

---

**Need help with storage issues?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or run `./diagnostics/check_raid_status.sh` for health checks.
