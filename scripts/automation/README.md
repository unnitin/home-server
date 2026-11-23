# 🤖 Automation Module

Automation layer managing LaunchD services, scheduled tasks, system monitoring, and maintenance.

## 📋 Scripts

### **Service Management**

#### **configure_launchd.sh**
**Purpose**: Install comprehensive recovery automation using LaunchD  
**Usage**: Run during setup to enable graceful reboot recovery  
**Features**: Template-based plist installation, dependency-ordered startup
**Placeholders**: `__REPO__` (this checkout, wherever it lives), `__HOME__`, `__USER__`. A plist with an unfilled placeholder is refused
**Preview**: `TEST_MODE=1 LAUNCHD_PLIST_DIR=/tmp/plists scripts/automation/configure_launchd.sh` (or `--render-only`) renders without loading anything
**Note**: Don't run the jobs from a checkout under `~/Documents`. macOS blocks LaunchD jobs from executing scripts there (exit 126); see D19 in `docs/mcp-refactor/01-assessment.md`

### **System Monitoring**

#### **check_updates.sh**
**Purpose**: Automated system update checking and notification  
**Usage**: Run by LaunchD automation on schedule  
**Features**: Checks Homebrew packages, monitors container images

### **Media Automation Setup**

#### **setup_media_processing.sh**
**Purpose**: Sets up the complete media processing system for automated Plex organization  
**Usage**: `./scripts/automation/setup_media_processing.sh`  
**Features**: Creates staging directories, sets up logging, configures permissions

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`, `infrastructure/`, `services/`  
**Used by**: LaunchD services, manual maintenance

## 📁 Module Architecture

```
scripts/automation/
├── configure_launchd.sh         # LaunchD service setup
├── check_updates.sh            # Update monitoring
├── setup_media_processing.sh   # Media automation setup
└── README.md                   # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
