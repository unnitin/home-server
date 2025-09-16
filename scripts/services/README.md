# 🚀 Services Module

Application layer managing Plex, Immich, web services, and data import/export.

## 📋 Scripts

### **Container Services**

#### **deploy_containers.sh**
**Purpose**: Deploy and start containerized services (Immich)  
**Usage**: Run during setup and for service recovery  
**Dependencies**: `../infrastructure/compose_wrapper.sh`, Docker runtime

### **Native Applications**

#### **install_plex.sh**
**Purpose**: Install Plex Media Server as native macOS application  
**Usage**: Run during setup when Plex is requested  
**Dependencies**: Internet connection

#### **start_plex_safe.sh**
**Purpose**: Safely start Plex with Tailscale port conflict resolution  
**Usage**: Called by LaunchD `io.homelab.plex` service  
**Features**: Detects and resolves port 32400 conflicts

#### **configure_plex_direct.sh**
**Purpose**: Configure Plex to use direct mount paths (no symlinks)  
**Usage**: Run during setup to set metadata and transcoding paths  
**Dependencies**: Plex Media Server installed

### **Web Services**

#### **enable_landing.sh**
**Purpose**: Enable landing page with direct service access via Tailscale  
**Usage**: Run during setup and by automation to configure web access  
**Dependencies**: Tailscale, Python 3, `web/index.html`

### **Data Management**

#### **import_takeout.sh**
**Purpose**: Import Google Takeout archives into Immich photo management  
**Usage**: `./scripts/services/import_takeout.sh /path/to/Takeout.zip`  
**Features**: Extracts Google Photos, organizes by date, bulk imports

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`, `infrastructure/`  
**Used by**: `automation/`, `media/`

## 📁 Module Architecture

```
scripts/services/
├── deploy_containers.sh    # Container service deployment
├── install_plex.sh         # Plex Media Server setup
├── start_plex_safe.sh      # Safe Plex startup
├── configure_plex_direct.sh # Plex direct path configuration
├── enable_landing.sh       # Landing page service
├── import_takeout.sh       # Google Takeout import
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
