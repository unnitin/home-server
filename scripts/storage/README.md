# 💾 Storage Module

Storage layer managing RAID creation, disk preparation, mounting, and storage dependencies.

## 📋 Scripts

### **Core RAID Management**

#### **create_ssd_raid.sh**
**Purpose**: Create RAID 1 mirror from SSD drives (warmstore)  
**Usage**: Run during setup with `SSD_DISKS` environment variable  
**Creates**: `/Volumes/warmstore` RAID mirror  
**Dependencies**: `lib/raid_common.sh`

#### **create_nvme_raid.sh**  
**Purpose**: Create RAID 1 mirror from NVMe drives (faststore)  
**Usage**: Run during setup with `NVME_DISKS` environment variable  
**Creates**: `/Volumes/faststore` RAID mirror  
**Dependencies**: `lib/raid_common.sh`

#### **create_hdd_raid.sh**
**Purpose**: Create RAID 1 mirror from HDD drives (coldstore)  
**Usage**: Run during setup with `COLD_DISKS` environment variable  
**Creates**: `/Volumes/coldstore` RAID mirror  
**Dependencies**: `lib/raid_common.sh`

#### **format_and_mount.sh**
**Purpose**: Format and mount all created RAID volumes  
**Usage**: Run after RAID creation to make volumes available  
**Dependencies**: `diskutil`, AppleRAID volumes

### **Maintenance & Utilities**

#### **rebuild_storage.sh**
**Purpose**: Manual RAID rebuild utility for storage maintenance  
**Usage**: `./scripts/storage/rebuild_storage.sh [warmstore|faststore|coldstore]`  
**Dependencies**: Individual RAID creation scripts, service management

#### **cleanup_disks.sh**
**Purpose**: Securely erase and prepare disks for RAID use  
**Usage**: `RAID_I_UNDERSTAND_DATA_LOSS=1 ./scripts/storage/cleanup_disks.sh disk6 [disk7...]`  
**Safety**: Requires explicit data loss acknowledgment

#### **preclean_disks.sh**
**Purpose**: Prepare disks for RAID creation by cleaning existing data  
**Usage**: Run during setup when rebuilding storage  
**Dependencies**: `cleanup_disks.sh`

### **Mount & Dependency Management**

#### **setup_direct_mounts.sh**
**Purpose**: Create direct mount directory structure without symlinks for clean service integration  
**Usage**: Called by setup scripts and LaunchD `io.homelab.storage` service  
**Features**: Service-specific directories, permission handling, data-aware operations

#### **wait_for_storage.sh**
**Purpose**: Ensure storage prerequisites are ready before starting dependent services  
**Usage**: Called by LaunchD `io.homelab.compose.immich` service  
**Features**: Waits up to 5 minutes for warmstore RAID availability

## 📁 Library

### **lib/raid_common.sh**
**Purpose**: Shared RAID creation and management utilities  
**Usage**: `source "$(dirname "$0")/lib/raid_common.sh"` (from RAID scripts)  
**Key Functions**: Disk validation, RAID creation parameters, AppleRAID wrappers

## 🔗 Module Dependencies

**Depends on**: `core/` for health checks  
**Used by**: `services/`, `automation/`, `media/`

## 📁 Module Architecture

```
scripts/storage/
├── lib/
│   └── raid_common.sh      # Shared RAID utilities
├── create_ssd_raid.sh      # SSD RAID creation
├── create_nvme_raid.sh     # NVMe RAID creation  
├── create_hdd_raid.sh      # HDD RAID creation
├── format_and_mount.sh     # RAID formatting
├── rebuild_storage.sh      # Storage rebuild utility
├── cleanup_disks.sh        # Disk preparation
├── preclean_disks.sh       # Pre-RAID cleanup
├── setup_direct_mounts.sh  # Direct mount directory structure
├── wait_for_storage.sh     # Storage dependency check
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
