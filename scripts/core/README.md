# 🔧 Core Module

Foundation layer providing system bootstrap, environment setup, and health checking functionality.

## 📋 Scripts

### **environment.sh**
**Purpose**: Shared configuration for every module (D12). Sets `HOMELAB_REPO` and every `HOMELAB_*` value from `config/homelab.env`, which is generated from the manifest `config/homelab.yaml`, then the per-machine overrides in `config/homelab.local.env`  
**Usage**: `source "${SCRIPT_DIR}/../core/environment.sh"` (source it; don't run it)  
**Features**: Needs no Python (the generated file is committed); values the caller already set win; helpers `homelab_tier_mount <tier>`, `homelab_is_mounted <path>` (diskutil, not folder existence), and `log_info`/`log_warn`/`log_error` in the CLAUDE.md format unless the script defines its own  
**Dependencies**: None (core module)

### **fix_permissions.sh**
**Purpose**: Fix script permissions across the repository  
**Usage**: `./scripts/core/fix_permissions.sh`  
**Dependencies**: None  
**Used By**: Manual maintenance

### **ensure_power_settings.sh**
**Purpose**: Monitor and maintain Mac mini power settings for 24/7 server operation  
**Usage**: Called automatically by LaunchD `io.homelab.powermgmt` service  
**Dependencies**: `pmset` command  
**Used By**: LaunchD automation (powermgmt service)

### **health_check.sh**
**Purpose**: Health check with recovery guidance: every LaunchD job in the manifest (held jobs shown as held), every tier's mount, and every service's health URL  
**Usage**: `./scripts/core/health_check.sh [--auto-recover]` (`--auto-recover` starts Colima and Plex and restarts the landing job; storage is never repaired automatically)  
**Dependencies**: `environment.sh` (the manifest)  
**Used By**: Manual troubleshooting, automated recovery

### **check_storage_usage.sh**
**Purpose**: Usage of every tier in the manifest, against each tier's own warn and crit thresholds. A tier counts only when `diskutil` says a volume is mounted there  
**Usage**: `./scripts/core/check_storage_usage.sh` (exit 0 = every mounted tier below warn, 1 = at least one at warn or crit)  
**Dependencies**: `environment.sh` (the manifest), `df`, `diskutil`  
**Used By**: Manual monitoring, storage management

## 🔗 Module Dependencies

**Depends on**: None (foundation layer)  
**Used by**: All other modules for health checks and system validation

## 📁 Module Architecture

```
scripts/core/
├── fix_permissions.sh      # Script permission management
├── ensure_power_settings.sh # Power management monitoring  
├── health_check.sh         # System health validation
├── check_storage_usage.sh  # Storage usage monitoring
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
