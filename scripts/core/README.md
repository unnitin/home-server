# 🔧 Core Module

Foundation layer providing system bootstrap, environment setup, and health checking functionality.

## 📋 Scripts

### **environment.sh**
**Purpose**: Shared configuration for every module (D12). Sets `HOMELAB_REPO` and every `HOMELAB_*` value from `config/homelab.env`, which is generated from the manifest `config/homelab.yaml`, then the per-machine overrides in `config/homelab.local.env`  
**Usage**: `source "${SCRIPT_DIR}/../core/environment.sh"` (source it; don't run it)  
**Features**: Needs no Python (the generated file is committed); values the caller already set win; `homelab_tier_mount <tier>` prints a tier's mount point  
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
**Purpose**: Comprehensive system health check with recovery guidance  
**Usage**: `./scripts/core/health_check.sh [--auto-recover]`  
**Dependencies**: System services  
**Used By**: Manual troubleshooting, automated recovery

### **check_storage_usage.sh**
**Purpose**: Monitor storage usage on faststore and warmstore with color-coded status  
**Usage**: `./scripts/core/check_storage_usage.sh`  
**Dependencies**: `df` command  
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
