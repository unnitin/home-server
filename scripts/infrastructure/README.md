# 🏗️ Infrastructure Module

Infrastructure layer managing Docker runtime, networking, VPN, and system configuration.

## 📋 Scripts

### **Container Runtime**

#### **install_docker.sh**
**Purpose**: Install and configure Colima Docker runtime for containers  
**Usage**: Run during setup to enable containerized services  
**Dependencies**: Homebrew

#### **start_docker.sh**
**Purpose**: Start Colima Docker runtime with proper configuration  
**Usage**: Run during setup and boot automation  
**Features**: Sizes a new VM from the manifest (`services.colima.resources`: 4 CPUs, 6 GB, 60 GB disk; `COLIMA_CPU`/`COLIMA_MEM`/`COLIMA_DISK` override). Starts an existing VM as it is; only ever grows the disk

#### **compose_wrapper.sh**
**Purpose**: Standardized Docker Compose command wrapper  
**Usage**: `./scripts/infrastructure/compose_wrapper.sh /path/to/service [compose-args]`  
**Features**: Automatic working directory management, environment file handling

### **Networking & VPN**

#### **install_tailscale.sh**
**Purpose**: Install Tailscale VPN for secure remote access  
**Usage**: Run during setup when remote access is needed  
**Dependencies**: Internet connection

#### **configure_https.sh**
**Purpose**: Configure HTTPS serving and DNS resolution for Tailscale domains  
**Usage**: Run during setup after Tailscale installation  
**Features**: Sets up permanent DNS resolution, configures HTTPS serving

#### **apply_tailscale_serve.sh**
**Purpose**: Publish services to the tailnet over HTTPS from the single list in `config/tailscale_serve.txt` (landing 443, Immich 2283, Plex 32400, Jellyfin 8096, MCP 8765)
**Usage**: `scripts/infrastructure/apply_tailscale_serve.sh [--dry-run] [--wait SECONDS]`. Run by `services/enable_landing.sh` (LaunchD `io.homelab.landing`) and `configure_https.sh`. `TEST_MODE=1` implies `--dry-run`
**Behavior**: Adds a missing mapping once its backend answers, repoints wrong ones, never resets, and leaves undeclared mappings alone. Serve only, never Funnel

### **System Configuration**

#### **configure_power.sh**
**Purpose**: Configure Mac mini for 24/7 headless server operation  
**Usage**: Run during setup or manually to optimize power management  
**Features**: Prevents system sleep, optimizes settings for headless operation

## 📁 Library

### **lib/compose_helpers.sh**
**Purpose**: Compose shim for Immich: runs `compose_wrapper.sh` in the folder the manifest names (`services.immich.compose_dir`), from any working folder  
**Usage**: `source scripts/infrastructure/lib/compose_helpers.sh && compose ps`  
**Key Functions**: `compose ARGS...`

### **lib/tailscale.sh**
**Purpose**: Find and run the Tailscale CLI, which the Mac app keeps inside its bundle instead of on PATH
**Usage**: `source scripts/infrastructure/lib/tailscale.sh`
**Key Functions**: `tailscale_cli`, `ts` (retries with non-interactive `sudo -n`), `ts_serve_mappings`, `ts_funnel_enabled`, `ts_hostname`

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`  
**Used by**: `services/`, `automation/`

## 📁 Module Architecture

```
scripts/infrastructure/
├── lib/
│   ├── compose_helpers.sh   # Docker Compose utilities
│   └── tailscale.sh         # Tailscale CLI helpers
├── apply_tailscale_serve.sh # Tailnet HTTPS mappings
├── install_docker.sh       # Docker runtime setup
├── start_docker.sh         # Docker startup
├── compose_wrapper.sh      # Compose command wrapper
├── install_tailscale.sh    # VPN installation
├── configure_https.sh      # HTTPS & DNS setup
├── configure_power.sh      # Power management setup
└── README.md              # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
