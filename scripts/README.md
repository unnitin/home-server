# 🛠️ Scripts Directory Reference

**Before adding or modifying any script, consult this reference to understand existing functionality and avoid duplication.**

---

## 📋 **Quick Reference Index**

| Script | Category | Purpose | Used By |
|--------|----------|---------|---------|
| [`_compose.sh`](#_composesh) | Helper | Docker Compose utilities | 37_enable_simple_landing.sh, 80_check_updates.sh, 91_configure_https_dns.sh |
| [`_raid_common.sh`](#_raid_commonsh) | Helper | RAID creation utilities | 10_create_raid10_ssd.sh, 11_create_raid10_nvme.sh, 13_create_raid_coldstore.sh |
| [`09_preclean_disks_for_raid.sh`](#09_preclean_disks_for_raidsh) | Storage | Prepare disks for RAID | setup_full.sh, setup_flags.sh |
| [`09_rebuild_storage.sh`](#09_rebuild_storagesh) | Storage | Manual RAID rebuild | Manual use only |
| [`10_create_raid10_ssd.sh`](#10_create_raid10_ssdsh) | Storage | Create SSD RAID mirror | setup_full.sh, setup_flags.sh, 09_rebuild_storage.sh |
| [`11_create_raid10_nvme.sh`](#11_create_raid10_nvmesh) | Storage | Create NVMe RAID mirror | setup_full.sh, setup_flags.sh, 09_rebuild_storage.sh |
| [`12_format_and_mount_raids.sh`](#12_format_and_mount_raidssh) | Storage | Format and mount RAIDs | setup_full.sh, setup_flags.sh, 09_rebuild_storage.sh |
| [`13_create_raid_coldstore.sh`](#13_create_raid_coldstorresh) | Storage | Create HDD RAID mirror | setup_full.sh, setup_flags.sh, 09_rebuild_storage.sh |
| [`20_install_colima_docker.sh`](#20_install_colima_dockersh) | Infrastructure | Install Docker runtime | setup_full.sh, setup_flags.sh |
| [`21_start_colima.sh`](#21_start_colimash) | Infrastructure | Start Docker runtime | setup_full.sh, setup_flags.sh, LaunchD |
| [`30_deploy_services.sh`](#30_deploy_servicessh) | Services | Deploy container services | setup_full.sh, setup_flags.sh |
| [`31_install_native_plex.sh`](#31_install_native_plexsh) | Services | Install Plex Media Server | setup_full.sh, setup_flags.sh |
| [`37_enable_simple_landing.sh`](#37_enable_simple_landingsh) | Web | Landing page + HTTPS proxy | setup_full.sh, LaunchD, Manual |
| [`40_configure_launchd.sh`](#40_configure_launchdsh) | Automation | Install recovery automation | setup_full.sh, setup_flags.sh |
| [`70_takeout_to_immich.sh`](#70_takeout_to_immichsh) | Data | Import Google Takeout | Manual |
| [`80_check_updates.sh`](#80_check_updatessh) | Maintenance | System update checker | LaunchD io.homelab.updatecheck |
| [`90_install_tailscale.sh`](#90_install_tailscalesh) | Network | Install VPN service | setup_full.sh, setup_flags.sh |
| [`91_configure_https_dns.sh`](#91_configure_https_dnssh) | Network | Configure HTTPS serving | setup_full.sh, setup_flags.sh |
| [`92_configure_power.sh`](#92_configure_powersh) | Network | Configure power management | setup_full.sh, setup_flags.sh, Manual |
| [`cleanup_disks.sh`](#cleanup_diskssh) | Storage | Erase disk for RAID | 09_preclean_disks_for_raid.sh |
| [`compose_helper.sh`](#compose_helpersh) | Helper | Docker Compose wrapper | 30_deploy_services.sh, _compose.sh, 09_rebuild_storage.sh, LaunchD io.homelab.compose.immich |
| [`ensure_power_settings.sh`](#ensure_power_settingssh) | Utility | Monitor power settings | LaunchD io.homelab.powermgmt |
| [`cleanup_disks.sh`](#cleanup_diskssh) | Storage | Erase disk for RAID | 09_preclean_disks_for_raid.sh |
| [`compose_helper.sh`](#compose_helpersh) | Helper | Docker Compose wrapper | 30_deploy_services.sh, _compose.sh, 09_rebuild_storage.sh, LaunchD io.homelab.compose.immich |
| [`ensure_storage_mounts.sh`](#ensure_storage_mountssh) | Storage | Recovery mount points | LaunchD io.homelab.storage |
| [`make_executable.sh`](#make_executablesh) | Utility | Fix script permissions | Manual |
| [`post_boot_health_check.sh`](#post_boot_health_checksh) | Diagnostics | System health check | Manual |
| [`start_plex_safe.sh`](#start_plex_safesh) | Services | Safe Plex startup | LaunchD io.homelab.plex |
| [`wait_for_storage.sh`](#wait_for_storagesh) | Utility | Storage dependency check | LaunchD io.homelab.compose.immich |

---

## 📚 **Detailed Script Documentation**

### **Helper/Library Scripts** 🔧

#### `_compose.sh`
**Purpose**: Provides Docker Compose utility functions and environment setup  
**Usage**: `source scripts/_compose.sh` (from other scripts)  
**Key Functions**: 
- Environment validation
- Compose command abstraction
- Error handling utilities

**Dependencies**: None  
**Used By**: Various container management scripts

---

#### `_raid_common.sh`
**Purpose**: Shared RAID creation and management utilities  
**Usage**: `source scripts/_raid_common.sh` (from RAID scripts)  
**Key Functions**:
- Disk validation and preparation
- RAID creation parameters
- AppleRAID command wrappers

**Dependencies**: `diskutil`  
**Used By**: All RAID creation scripts (`10_*.sh`, `11_*.sh`, `13_*.sh`)

---

#### `compose_helper.sh`
**Purpose**: Standardized Docker Compose command wrapper  
**Usage**: `./scripts/compose_helper.sh /path/to/service [compose-args]`  
**Features**:
- Automatic working directory management
- Environment file handling
- Error reporting and logging

**Dependencies**: Docker, `docker-compose`  
**Used By**: `30_deploy_services.sh`, LaunchD automation, manual operations

---

### **Storage Management Scripts** 💾

#### `09_preclean_disks_for_raid.sh`
**Purpose**: Prepare disks for RAID creation by cleaning existing data  
**Usage**: Run during setup when rebuilding storage  
**Process**:
1. Identifies disks from environment variables
2. Calls `cleanup_disks.sh` for each disk set
3. Validates disk readiness for RAID

**Environment Variables**: `SSD_DISKS`, `NVME_DISKS`, `COLD_DISKS`  
**Dependencies**: `cleanup_disks.sh`  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `09_rebuild_storage.sh`
**Purpose**: Manual RAID rebuild utility for storage maintenance  
**Usage**: `./scripts/09_rebuild_storage.sh [warmstore|faststore|coldstore]`  
**Process**:
1. Stops dependent services (Immich)
2. Rebuilds specified RAID tier
3. Remounts storage
4. Restarts services

**Dependencies**: Individual RAID creation scripts, service management  
**Used By**: Manual maintenance operations

---

#### `10_create_raid10_ssd.sh`
**Purpose**: Create RAID 1 mirror from SSD drives (warmstore)  
**Usage**: Run during setup with `SSD_DISKS` environment variable  
**Creates**: `/Volumes/warmstore` RAID mirror  
**Dependencies**: `_raid_common.sh`, `diskutil appleRAID`  
**Used By**: `setup_full.sh`, `setup_flags.sh`, `09_rebuild_storage.sh`

---

#### `11_create_raid10_nvme.sh`
**Purpose**: Create RAID 1 mirror from NVMe drives (faststore)  
**Usage**: Run during setup with `NVME_DISKS` environment variable  
**Creates**: `/Volumes/faststore` RAID mirror  
**Dependencies**: `_raid_common.sh`, `diskutil appleRAID`  
**Used By**: `setup_full.sh`, `setup_flags.sh`, `09_rebuild_storage.sh`

---

#### `12_format_and_mount_raids.sh`
**Purpose**: Format and mount all created RAID volumes  
**Usage**: Run after RAID creation to make volumes available  
**Process**:
1. Detects available AppleRAID sets
2. Formats with APFS if needed
3. Mounts at proper locations
4. Creates directory structure

**Dependencies**: `diskutil`, AppleRAID volumes  
**Used By**: `setup_full.sh`, `setup_flags.sh`, `09_rebuild_storage.sh`

---

#### `13_create_raid_coldstore.sh`
**Purpose**: Create RAID 1 mirror from HDD drives (coldstore)  
**Usage**: Run during setup with `COLD_DISKS` environment variable  
**Creates**: `/Volumes/coldstore` RAID mirror  
**Dependencies**: `_raid_common.sh`, `diskutil appleRAID`  
**Used By**: `setup_full.sh`, `setup_flags.sh`, `09_rebuild_storage.sh`

---

#### `cleanup_disks.sh`
**Purpose**: Securely erase and prepare disks for RAID use  
**Usage**: `RAID_I_UNDERSTAND_DATA_LOSS=1 ./scripts/cleanup_disks.sh disk6 [disk7...]`  
**Safety**: Requires explicit data loss acknowledgment  
**Process**:
1. Validates disk identifiers
2. Unmounts existing volumes
3. Securely erases disk contents
4. Prepares for RAID creation

**Dependencies**: `diskutil`  
**Used By**: `09_preclean_disks_for_raid.sh`, manual disk preparation

---

#### `ensure_storage_mounts.sh`
**Purpose**: Automated storage mount point recovery for boot automation  
**Usage**: Called by LaunchD `io.homelab.storage` service  
**Features**:
- Graceful permission handling
- Detailed logging and fallback guidance
- Status reporting for failed operations

**Process**:
1. Waits for warmstore availability
2. Creates Media, Photos, Archive mount points
3. Provides manual recovery commands if permissions fail

**Dependencies**: `/Volumes/warmstore`  
**Used By**: LaunchD automation (storage service)

---

### **Infrastructure Scripts** 🏗️

#### `20_install_colima_docker.sh`
**Purpose**: Install and configure Colima Docker runtime for containers  
**Usage**: Run during setup to enable containerized services  
**Process**:
1. Installs Colima via Homebrew
2. Configures VM settings for optimal performance
3. Validates Docker functionality

**Dependencies**: Homebrew  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `21_start_colima.sh`
**Purpose**: Start Colima Docker runtime with proper configuration  
**Usage**: Run during setup and boot automation  
**Features**:
- Detects existing Colima instances
- Handles upgrade scenarios
- Validates startup success

**Dependencies**: Colima installation  
**Used By**: `setup_full.sh`, `setup_flags.sh`, LaunchD automation

---

### **Service Management Scripts** 🚀

#### `30_deploy_services.sh`
**Purpose**: Deploy and start containerized services (Immich)  
**Usage**: Run during setup and for service recovery  
**Process**:
1. Pulls latest container images
2. Starts services with docker-compose
3. Validates service health

**Dependencies**: `compose_helper.sh`, Docker runtime  
**Used By**: `setup_full.sh`, `setup_flags.sh`, manual recovery

---

#### `31_install_native_plex.sh`
**Purpose**: Install Plex Media Server as native macOS application  
**Usage**: Run during setup when Plex is requested  
**Process**:
1. Downloads latest Plex installer
2. Installs to /Applications
3. Configures basic settings

**Dependencies**: Internet connection  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `start_plex_safe.sh`
**Purpose**: Safely start Plex with Tailscale port conflict resolution  
**Usage**: Called by LaunchD `io.homelab.plex` service  
**Features**:
- Detects and resolves port 32400 conflicts
- Temporarily disables Tailscale serving during startup
- Re-enables Tailscale proxy after Plex binds port

**Dependencies**: Plex installation, Tailscale  
**Used By**: LaunchD automation (Plex service)

---

### **Web and Networking Scripts** 🌐

#### `37_enable_simple_landing.sh`
**Purpose**: Enable landing page with direct service access via Tailscale  
**Usage**: Run during setup and by automation to configure web access  
**Features**:
- Starts Python HTTP server for landing page
- Configures Tailscale HTTPS proxies
- Provides direct access to all services

**Dependencies**: Tailscale, Python 3, `web/index.html`  
**Used By**: `setup_full.sh`, LaunchD automation (landing service)

---

#### `90_install_tailscale.sh`
**Purpose**: Install Tailscale VPN for secure remote access  
**Usage**: Run during setup when remote access is needed  
**Process**:
1. Downloads and installs Tailscale
2. Guides through device registration
3. Configures basic networking

**Dependencies**: Internet connection  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `91_configure_https_dns.sh`
**Purpose**: Configure HTTPS serving and DNS resolution for Tailscale domains  
**Usage**: Run during setup after Tailscale installation  
**Features**:
- Sets up permanent DNS resolution for .ts.net domains
- Configures HTTPS serving for all services
- Validates network connectivity

**Dependencies**: Tailscale installation, `scripts/90_install_tailscale.sh`  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `92_configure_power.sh`
**Purpose**: Configure Mac mini for 24/7 headless server operation  
**Usage**: Run during setup or manually to optimize power management  
**Features**:
- Prevents system sleep while maintaining service availability
- Optimizes display and disk sleep for headless operation
- Enables network wake capabilities for remote management
- Disables power-saving features that interfere with server operation

**Process**:
1. Disables system sleep (sleep=0) for 24/7 availability
2. Sets minimal display sleep (displaysleep=1) for headless optimization
3. Prevents disk sleep (disksleep=0) for immediate access
4. Enables wake-on-network for remote management
5. Optimizes settings for SSD/NVMe storage

**Dependencies**: `sudo` access for `pmset` commands  
**Used By**: `setup_full.sh`, `setup_flags.sh`, manual server optimization

---

### **Automation and Maintenance Scripts** 🤖

#### `40_configure_launchd.sh`
**Purpose**: Install comprehensive recovery automation using LaunchD  
**Usage**: Run during setup to enable graceful reboot recovery  
**Features**:
- Template-based plist installation with variable substitution
- Dependency-ordered service startup
- Comprehensive logging and error handling

**Process**:
1. Processes plist templates from `launchd/` directory
2. Substitutes environment variables (`__HOME__`, `__USER__`)
3. Installs and enables services in dependency order

**Dependencies**: Plist templates in `launchd/` directory  
**Used By**: `setup_full.sh`, `setup_flags.sh`

---

#### `80_check_updates.sh`
**Purpose**: Automated system update checking and notification  
**Usage**: Run by LaunchD automation on schedule  
**Features**:
- Checks Homebrew packages
- Monitors container images
- Reports available updates

**Dependencies**: Homebrew, Docker  
**Used By**: LaunchD automation (updatecheck service)

---

### **Data Management Scripts** 📊

#### `70_takeout_to_immich.sh`
**Purpose**: Import Google Takeout archives into Immich photo management  
**Usage**: `./scripts/70_takeout_to_immich.sh /path/to/Takeout.zip`  
**Features**:
- Extracts Google Photos from Takeout
- Organizes photos by date
- Bulk imports to Immich

**Dependencies**: Immich installation, `unzip`  
**Used By**: Manual data migration

---

### **Utility and Diagnostic Scripts** 🔧

#### `make_executable.sh`
**Purpose**: Fix script permissions across the repository  
**Usage**: `./scripts/make_executable.sh`  
**Process**:
1. Finds all `.sh` files
2. Makes them executable
3. Reports changes made

**Dependencies**: None  
**Used By**: Manual maintenance

---

#### `post_boot_health_check.sh`
**Purpose**: Comprehensive system health check with recovery guidance  
**Usage**: `./scripts/post_boot_health_check.sh`  
**Features**:
- Checks LaunchD service status
- Validates storage mounts
- Tests service connectivity
- Provides specific recovery commands

**Dependencies**: System services  
**Used By**: Manual troubleshooting

---

#### `ensure_power_settings.sh`
**Purpose**: Monitor and maintain Mac mini power management settings  
**Usage**: Called automatically by LaunchD `io.homelab.powermgmt` service  
**Features**:
- Monitors power settings every hour to detect changes
- Automatically restores server-optimized settings if modified
- Logs power setting verification and restoration activities
- Provides manual recovery commands if automatic restoration fails

**Process**:
1. Checks current power settings against expected values
2. Detects changes from external sources (system updates, manual changes)
3. Calls `92_configure_power.sh` to restore settings if needed
4. Logs all activities for monitoring and troubleshooting

**Dependencies**: `92_configure_power.sh`, `pmset` command  
**Used By**: LaunchD automation (powermgmt service)

#### `wait_for_storage.sh`
**Purpose**: Ensure storage prerequisites are ready before starting dependent services  
**Usage**: Called automatically by LaunchD `io.homelab.compose.immich` service  
**Features**:
- Waits up to 5 minutes for warmstore RAID availability
- Verifies `/Volumes/Photos` symlink exists and is accessible  
- Prevents timing race conditions in service startup
- Comprehensive logging of storage readiness checks

**Process**:
1. Waits for `/Volumes/warmstore` RAID array to be mounted
2. Waits for `/Volumes/Photos` symlink to be created by storage service
3. Verifies symlink target directory is accessible
4. Logs complete storage architecture status on success

**Dependencies**: `ensure_storage_mounts.sh`, AppleRAID, warmstore RAID  
**Used By**: LaunchD automation (Immich service dependency)

---


## 🚨 **Before Adding New Scripts**

### **✅ Checklist:**

1. **📋 Check this README** - Ensure functionality doesn't already exist
2. **🔍 Search existing scripts** - Look for similar patterns or utilities
3. **🎯 Define clear purpose** - What specific problem does this solve?
4. **📂 Choose appropriate category** - Helper, Storage, Infrastructure, Services, etc.
5. **🔗 Identify dependencies** - What other scripts or tools are needed?
6. **📝 Document usage** - How will this be called and by what?
7. **🧪 Plan testing** - How will you verify it works?

### **📋 Naming Convention:**
- **Numbers**: `[0-9][0-9]_` for setup phase scripts
- **Descriptive**: Clear action and target (e.g., `install_`, `configure_`, `start_`)
- **Underscores**: Use `_` for word separation, not hyphens
- **Extension**: Always `.sh` for shell scripts

### **🔧 Integration Points:**
- **Setup scripts**: Add to `setup_full.sh` and `setup_flags.sh`
- **Automation scripts**: Add plist template to `launchd/` directory
- **Helper scripts**: Use `source` pattern for shared functionality
- **Utility scripts**: Document in appropriate category above

---

## 🔗 **Related Documentation**

- **📖 [Setup Process](../setup/README.md)** - How scripts integrate into setup
- **🤖 [LaunchD Automation](../launchd/README.md)** - Automation service details
- **🔍 [Diagnostics](../diagnostics/README.md)** - Health checking and troubleshooting
- **📚 [Main Documentation](../docs/README.md)** - Complete system overview

---

**💡 Remember: This README should be updated whenever scripts are added, removed, or significantly modified!**
