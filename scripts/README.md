# 🛠️ Scripts Directory Reference

**Modular script architecture with clear separation of concerns and dependencies.**

---

## 🏗️ **Modular Architecture Overview**

The scripts are organized into 6 functional modules with layered dependencies:

```
scripts/
├── core/           # 🔧 System bootstrap & environment (4 scripts)
├── storage/        # 💾 RAID & storage management (10 scripts + lib)
├── infrastructure/ # 🏗️ Docker, networking, VPN (7 scripts + lib)
├── services/       # 🚀 Application deployment (10 scripts)
├── automation/     # 🤖 LaunchD & maintenance (3 scripts)
├── media/          # 📁 Media processing (5 scripts)
└── takeout/        # 📸 Google Photos import (2 scripts)
```

**Dependency Flow**: `core` → `storage` → `infrastructure` → `services` → `automation`/`media`

---

## 📋 **Quick Reference Index**

### **🔧 Core Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`core/fix_permissions.sh`](core/README.md#fix_permissionssh) | Fix script permissions | Manual maintenance |
| [`core/ensure_power_settings.sh`](core/README.md#ensure_power_settingssh) | Monitor power settings | LaunchD io.homelab.powermgmt |
| [`core/health_check.sh`](core/README.md#health_checksh) | System health validation | Manual troubleshooting |
| [`core/check_storage_usage.sh`](core/README.md#check_storage_usagesh) | Monitor storage usage | Manual monitoring |

### **💾 Storage Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`storage/lib/raid_common.sh`](storage/README.md#libraidcommonsh) | RAID utilities library | All RAID creation scripts |
| [`storage/create_ssd_raid.sh`](storage/README.md#create_ssd_raidsh) | Create SSD RAID mirror | setup_full.sh, setup_flags.sh |
| [`storage/create_nvme_raid.sh`](storage/README.md#create_nvme_raidsh) | Create NVMe RAID mirror | setup_full.sh, setup_flags.sh |
| [`storage/create_hdd_raid.sh`](storage/README.md#create_hdd_raidsh) | Create HDD RAID mirror | setup_full.sh, setup_flags.sh |
| [`storage/format_and_mount.sh`](storage/README.md#format_and_mountsh) | Format and mount RAIDs | setup_full.sh, setup_flags.sh |
| [`storage/cleanup_disks.sh`](storage/README.md#cleanup_diskssh) | Prepare disks for RAID | storage/preclean_disks.sh |
| [`storage/preclean_disks.sh`](storage/README.md#preclean_diskssh) | Pre-RAID cleanup | setup_full.sh, setup_flags.sh |
| [`storage/rebuild_storage.sh`](storage/README.md#rebuild_storagesh) | Manual RAID rebuild | Manual use only |
| [`storage/setup_direct_mounts.sh`](storage/README.md#setup_direct_mountssh) | Direct mount directory structure | LaunchD io.homelab.storage |
| [`storage/wait_for_storage.sh`](storage/README.md#wait_for_storagesh) | Storage dependency check | LaunchD io.homelab.compose.immich |

### **🏗️ Infrastructure Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`infrastructure/lib/compose_helpers.sh`](infrastructure/README.md#libcompose_helperssh) | Docker Compose utilities | Various container scripts |
| [`infrastructure/install_docker.sh`](infrastructure/README.md#install_dockersh) | Install Docker runtime | setup_full.sh, setup_flags.sh |
| [`infrastructure/start_docker.sh`](infrastructure/README.md#start_dockersh) | Start Docker runtime | setup_full.sh, setup_flags.sh, LaunchD |
| [`infrastructure/compose_wrapper.sh`](infrastructure/README.md#compose_wrappersh) | Docker Compose wrapper | services/deploy_containers.sh, LaunchD |
| [`infrastructure/install_tailscale.sh`](infrastructure/README.md#install_tailscalesh) | Install VPN service | setup_full.sh, setup_flags.sh |
| [`infrastructure/configure_https.sh`](infrastructure/README.md#configure_httpssh) | Configure HTTPS serving | setup_full.sh, setup_flags.sh |
| [`infrastructure/configure_power.sh`](infrastructure/README.md#configure_powersh) | Power management setup | setup_full.sh, setup_flags.sh |

### **🚀 Services Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`services/deploy_containers.sh`](services/README.md#deploy_containerssh) | Deploy container services | setup_full.sh, setup_flags.sh |
| [`services/install_jellyfin.sh`](services/README.md#install_jellyfinsh) | Install Jellyfin Media Server | setup_full.sh, setup_flags.sh |
| [`services/configure_jellyfin.sh`](services/README.md#configure_jellyfinsh) | Configure Jellyfin faststore paths | setup_full.sh, Manual |
| [`services/start_jellyfin_safe.sh`](services/README.md#start_jellyfin_safesh) | Safe Jellyfin startup | LaunchD io.homelab.jellyfin |
| [`services/install_plex.sh`](services/README.md#install_plexsh) | Install Plex Media Server | setup_full.sh, setup_flags.sh |
| [`services/start_plex_safe.sh`](services/README.md#start_plex_safesh) | Safe Plex startup | LaunchD io.homelab.plex |
| [`services/configure_plex_direct.sh`](services/README.md#configure_plex_directsh) | Configure Plex direct paths | setup_full.sh, Manual |
| [`services/enable_landing.sh`](services/README.md#enable_landingsh) | Landing page service | setup_full.sh, LaunchD |
| [`services/import_takeout.sh`](services/README.md#import_takeoutsh) | Google Takeout import wrapper | Manual |

### **🤖 Automation Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`automation/configure_launchd.sh`](automation/README.md#configure_launchdsh) | LaunchD service setup | setup_full.sh, setup_flags.sh |
| [`automation/check_updates.sh`](automation/README.md#check_updatessh) | Update monitoring | LaunchD io.homelab.updatecheck |
| [`automation/setup_media_processing.sh`](automation/README.md#setup_media_processingsh) | Media automation setup | setup_full.sh, setup_flags.sh |

### **📁 Media Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`media/processor.sh`](media/README.md#processorsh) | Main media processing orchestrator | media/watcher.sh, Manual |
| [`media/watcher.sh`](media/README.md#watchersh) | File system monitoring | LaunchD io.homelab.media.watcher |
| [`media/process_movie.sh`](media/README.md#process_moviesh) | Movie file processing | media/processor.sh |
| [`media/process_tv_show.sh`](media/README.md#process_tv_showsh) | TV show processing | media/processor.sh |
| [`media/process_collection.sh`](media/README.md#process_collectionsh) | Collection processing | media/processor.sh |

### **📸 Takeout Module**
| Script | Purpose | Used By |
|--------|---------|---------|
| [`takeout/enhanced_takeout_import.sh`](takeout/README.md#enhanced_takeout_importsh) | Enhanced Google Photos import | Manual |
| [`takeout/enhanced_takeout_import.py`](takeout/DOCUMENTATION.md) | Python implementation for import | enhanced_takeout_import.sh |

---

## 🔗 **Module Dependencies**

### **Dependency Hierarchy**
```
core/           # Foundation (no dependencies)
  ↑
storage/        # Depends on: core/
  ↑  
infrastructure/ # Depends on: core/, storage/
  ↑
services/       # Depends on: core/, storage/, infrastructure/
  ↑
automation/     # Depends on: all previous modules
  ↑
media/          # Depends on: core/, storage/, services/
```

---

## 📚 **Module Documentation**

Each module has its own detailed README:
- [🔧 Core Module](core/README.md)
- [💾 Storage Module](storage/README.md)  
- [🏗️ Infrastructure Module](infrastructure/README.md)
- [🚀 Services Module](services/README.md)
- [🤖 Automation Module](automation/README.md)
- [📁 Media Module](media/README.md)

---

**💡 This README reflects the new modular architecture. Each module contains focused functionality with clear dependencies.**
