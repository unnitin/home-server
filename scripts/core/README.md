# 🔧 Core Module

Foundation layer providing system bootstrap, environment setup, and health checking functionality.

## 📋 Scripts

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

## 🔗 Module Dependencies

**Depends on**: None (foundation layer)  
**Used by**: All other modules for health checks and system validation

## 📁 Module Architecture

```
scripts/core/
├── fix_permissions.sh      # Script permission management
├── ensure_power_settings.sh # Power management monitoring  
├── health_check.sh         # System health validation
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
