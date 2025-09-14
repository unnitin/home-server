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
**Features**: Detects existing instances, handles upgrades

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

### **System Configuration**

#### **configure_power.sh**
**Purpose**: Configure Mac mini for 24/7 headless server operation  
**Usage**: Run during setup or manually to optimize power management  
**Features**: Prevents system sleep, optimizes settings for headless operation

## 📁 Library

### **lib/compose_helpers.sh**
**Purpose**: Docker Compose utility functions and environment setup  
**Usage**: `source scripts/infrastructure/lib/compose_helpers.sh`  
**Key Functions**: Environment validation, compose command abstraction

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`  
**Used by**: `services/`, `automation/`

## 📁 Module Architecture

```
scripts/infrastructure/
├── lib/
│   └── compose_helpers.sh   # Docker Compose utilities
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
