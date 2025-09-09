# Mac Mini HomeServer (hakuna_mateti)

A complete, batteries-included setup for a Mac mini home server featuring **Native Plex**, **Immich** (self-hosted photos), secure **remote access via Tailscale**, and a scalable **storage architecture** using macOS AppleRAID.

## 🚀 Quick Start

**New to this setup?** → [**📋 Quick Start Guide**](docs/QUICKSTART.md)  
**Need environment variables?** → [**⚙️ Environment Setup**](docs/ENVIRONMENT.md)  
**Want detailed setup?** → [**📖 Detailed Setup Guide**](docs/SETUP.md)

## 📁 What You Get

### Core Services
- **🎬 Plex Media Server** (native app) - Stream movies, TV shows, music with hardware transcoding
- **📸 Immich** (Docker via Colima) - Self-hosted photo backup and browsing (Google Photos alternative)
- **🔒 Tailscale** - Secure remote access with HTTPS to your services from anywhere
- **🌐 Caddy Reverse Proxy** *(optional)* - Single URL access to all services

### Storage Architecture
- **⚡ faststore** (NVMe): High-speed storage for photos → `/Volumes/Photos`
- **💾 warmstore** (SSD): Media library storage → `/Volumes/Media`  
- **🗄️ coldstore** (HDD): Archive storage → `/Volumes/Archive`

**Storage Scaling**: 2 disks = mirror, 4 disks = RAID10. Rebuild scripts handle growth.

### Automation & Monitoring
- **🤖 LaunchD Jobs** - Auto-start services on boot
- **📊 Diagnostics Suite** - Health checks for all components
- **🔄 Update Checker** - Weekly automated update checks

## 📚 Documentation

### Getting Started
- [📋 **Quick Start Guide**](docs/QUICKSTART.md) - Get running in 30 minutes
- [⚙️ **Environment Variables**](docs/ENVIRONMENT.md) - Configuration reference
- [📖 **Detailed Setup Guide**](docs/SETUP.md) - Step-by-step comprehensive setup

### Service Guides  
- [🎬 **Plex Setup & Usage**](docs/PLEX.md) - Native Plex installation and configuration
- [📸 **Immich Setup & Usage**](docs/IMMICH.md) - Photo management and Google Takeout import
- [🔒 **Tailscale Setup & Usage**](docs/TAILSCALE.md) - Remote access configuration
- [🌐 **Reverse Proxy Setup**](docs/REVERSE-PROXY.md) - Single URL access with Caddy

### Advanced Topics
- [💾 **Storage Management**](docs/STORAGE.md) - RAID setup, growth, and backups
- [🤖 **Automation & LaunchD**](docs/AUTOMATION.md) - Auto-start and scheduled tasks
- [📊 **Diagnostics & Monitoring**](docs/DIAGNOSTICS.md) - Health checks and troubleshooting
- [🔧 **Troubleshooting**](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🎯 Setup Options

Choose your setup method:

### 1. Interactive Setup (Recommended for first-time users)
```bash
cd /Users/nitinsrivastava/Documents/home-server
setup/setup_full.sh
```

### 2. Quick Bootstrap (Safe preparation)
```bash
setup/setup.sh
```

### 3. Automated Setup (For advanced users)
```bash
setup/setup_flags.sh --all
```

## 🌟 Post-Setup: Using Your Server

After setup, you'll have access to:

### 🎬 Plex Media Server
- **Local**: http://localhost:32400/web
- **Remote**: https://your-macmini.tailnet.ts.net:32400
- **Via Proxy**: https://your-macmini.tailnet.ts.net/plex

### 📸 Immich Photo Management  
- **Local**: http://localhost:2283
- **Remote**: https://your-macmini.tailnet.ts.net
- **Via Proxy**: https://your-macmini.tailnet.ts.net/photos

### 🏠 Server Dashboard *(with reverse proxy)*
- **Home Page**: https://your-macmini.tailnet.ts.net
- One-click access to all services with status indicators

## 🗂️ Repository Structure

```
home-server/
├── 📄 README.md                    # This file - main navigation
├── 📁 docs/                       # 📚 Detailed documentation
│   ├── QUICKSTART.md              # Quick start guide
│   ├── SETUP.md                   # Detailed setup steps
│   ├── ENVIRONMENT.md             # Environment variables
│   ├── PLEX.md                    # Plex setup & usage
│   ├── IMMICH.md                  # Immich setup & usage
│   ├── TAILSCALE.md               # Remote access setup
│   ├── REVERSE-PROXY.md           # Reverse proxy guide
│   ├── STORAGE.md                 # Storage management
│   ├── AUTOMATION.md              # LaunchD & automation
│   ├── DIAGNOSTICS.md             # Monitoring & health checks
│   └── TROUBLESHOOTING.md         # Common issues
├── 🔧 setup/                      # Setup entry points
│   ├── setup.sh                   # Safe bootstrap
│   ├── setup_full.sh              # Interactive setup
│   ├── setup_flags.sh             # Automated setup
│   └── README.md                  # Setup documentation
├── 📜 scripts/                    # Individual setup scripts
├── 🐳 services/                   # Service configurations
│   ├── immich/                    # Immich Docker setup
│   └── caddy/                     # Reverse proxy config
├── 🤖 launchd/                    # Auto-start configurations
└── 🔍 diagnostics/                # Health check scripts
```

## 🚨 Important Notes

- **macOS Compatibility**: Tested on Apple Silicon macOS with Homebrew
- **Storage Rebuilds**: RAID operations are **destructive** - backup first!
- **Security**: All remote access uses Tailscale's encrypted mesh VPN
- **Updates**: Automated weekly update checks with manual approval

## 💡 Common Use Cases

### Fresh Installation
1. [📋 Follow Quick Start](docs/QUICKSTART.md)
2. [📖 Complete Detailed Setup](docs/SETUP.md) 
3. [📸 Import Google Photos](docs/IMMICH.md#google-takeout-import)

### Adding Storage
1. [💾 Plan storage expansion](docs/STORAGE.md#scaling-storage)
2. [🔧 Backup existing data](docs/STORAGE.md#backup-and-restore)
3. [⚡ Rebuild RAID arrays](docs/STORAGE.md#rebuilding-arrays)

### Remote Access Setup
1. [🔒 Install Tailscale](docs/TAILSCALE.md)
2. [🌐 Optional: Enable reverse proxy](docs/REVERSE-PROXY.md)
3. [📱 Configure mobile apps](docs/TAILSCALE.md#mobile-setup)

## 🆘 Need Help?

- **Setup Issues**: [🔧 Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- **Health Checks**: [📊 Diagnostics Guide](docs/DIAGNOSTICS.md)
- **Environment Config**: [⚙️ Environment Variables](docs/ENVIRONMENT.md)

---

**Ready to get started?** → [📋 **Quick Start Guide**](docs/QUICKSTART.md)