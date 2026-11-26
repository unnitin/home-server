# 🚀 Services Module

Application layer managing Jellyfin, Plex, Immich, web services, and data import/export.

## 📋 Scripts

### **Container Services**

#### **deploy_containers.sh**
**Purpose**: Deploy and start containerized services (Immich)  
**Usage**: Run during setup and for service recovery  
**Dependencies**: `../infrastructure/compose_wrapper.sh`, Docker runtime

### **Native Applications**

#### **install_jellyfin.sh**
**Purpose**: Install Jellyfin Media Server as native macOS application  
**Usage**: Run during setup for video streaming  
**Dependencies**: Internet connection
**Documentation**: [Jellyfin Setup Guide](../../docs/JELLYFIN.md)

#### **configure_jellyfin.sh**
**Purpose**: Configure Jellyfin to use faststore for metadata/transcoding  
**Usage**: Run after installation to optimize storage paths  
**Dependencies**: Jellyfin installed, faststore mounted

#### **lib/native_app.sh**
**Purpose**: `start_native_app <service>`: start a native app from the manifest safely (the steps the two start scripts share)  
**Usage**: `source scripts/services/lib/native_app.sh` (source it; don't run it)

#### **start_jellyfin_safe.sh**
**Purpose**: Start Jellyfin if it isn't answering  
**Usage**: Called by LaunchD `io.homelab.jellyfin`, or by hand  
**Features**: Steps in `lib/native_app.sh`, values from the manifest (app, health URL, port, data tier). Leaves a running app alone; won't start the app unless its data tier is really mounted; takes the tailnet mapping on its port down while it starts and puts the manifest's mappings back either way; waits up to `START_TIMEOUT` seconds (default 60)

#### **install_plex.sh**
**Purpose**: Install Plex Media Server as native macOS application  
**Usage**: Run during setup when Plex is requested  
**Dependencies**: Internet connection
**Documentation**: [Plex Setup Guide](../../docs/PLEX.md)

#### **start_plex_safe.sh**
**Purpose**: Start Plex if it isn't answering  
**Usage**: Called by LaunchD `io.homelab.plex`, or by hand  
**Features**: Steps in `lib/native_app.sh`, values from the manifest (app, health URL, port, data tier). Leaves a running app alone; won't start the app unless its data tier is really mounted; takes the tailnet mapping on its port down while it starts and puts the manifest's mappings back either way; waits up to `START_TIMEOUT` seconds (default 60)

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
├── install_jellyfin.sh     # Jellyfin Media Server setup
├── configure_jellyfin.sh   # Jellyfin storage configuration
├── start_jellyfin_safe.sh  # Safe Jellyfin startup
├── install_plex.sh         # Plex Media Server setup
├── start_plex_safe.sh      # Safe Plex startup
├── configure_plex_direct.sh # Plex direct path configuration
├── enable_landing.sh       # Landing page service
├── import_takeout.sh       # Google Takeout import
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
