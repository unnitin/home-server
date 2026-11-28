# 📋 Quick Start Guide

Get your Mac mini home server running in **30 minutes** with Plex, Immich, and secure remote access.

## 🎯 What You'll Have

After this guide:
- **🎬 Plex Media Server** running natively with hardware transcoding
- **📸 Immich** for photo backup and management (Google Photos alternative)  
- **🔒 Tailscale** for secure remote access from anywhere
- **💾 Storage** mounted and ready (optional RAID setup)

## ⚙️ Prerequisites

- Mac mini (Apple Silicon or Intel)
- macOS 12+ with admin access
- Internet connection
- *Optional*: External disks for storage arrays

## 🚀 Step-by-Step Setup

### 1. Bootstrap Environment (5 minutes)

```bash
cd /path/to/home-server
setup/setup.sh
```

This installs Homebrew and essential CLI tools safely.

### 2. Set Environment Variables (2 minutes)

**Required for Immich:**
```bash
# Copy the example environment file for Immich
cd services/immich
cp .env.example .env

# Edit and set IMMICH_DB_PASSWORD (required!)
${EDITOR:-nano} .env
```

**Optional - Storage Arrays:**  
*Skip this if you want to use existing drives or set up storage later.*

```bash
# For storage setup (⚠️ DESTRUCTIVE - backup first!)
export RAID_I_UNDERSTAND_DATA_LOSS=1

# Example: 2 SSDs for media storage (warmstore)
export SSD_DISKS="disk4 disk5"          # Check with: diskutil list

# Example: 2 NVMe drives for photo storage (faststore) 
export NVME_DISKS="disk2 disk3"         # Check with: diskutil list
```

> 💡 **Tip**: Run `diskutil list` to identify your disk IDs. Use whole disk IDs (like `disk4`), not partitions (like `disk4s1`).

### 3. Run Complete Setup (15 minutes)

**Option A: Interactive Setup (Recommended)**
```bash
setup/setup_full.sh
```
Guides you through each step with confirmations.

**Option B: Automated Setup**
```bash
setup/setup_flags.sh --all
```
Runs everything automatically (requires environment variables set).

**Option C: Manual Step-by-Step**
```bash
# Docker runtime
./scripts/infrastructure/install_docker.sh
./scripts/infrastructure/start_docker.sh

# Deploy Immich
./scripts/services/deploy_containers.sh

# Install Plex natively  
./scripts/services/install_plex.sh

# Set up autostart
./scripts/automation/configure_launchd.sh

# Install Tailscale
./scripts/infrastructure/install_tailscale.sh
```

### 4. Configure Remote Access (5 minutes)

```bash
# Connect to your Tailscale network
sudo tailscale up --accept-dns=true

# Enable HTTPS access to services
sudo tailscale serve --https=443   http://localhost:2283      # Immich
sudo tailscale serve --https=32400 http://localhost:32400      # Plex
```

### 5. Optional: Enable Reverse Proxy (3 minutes)

For single-URL access in browsers:

```bash
./scripts/services/enable_landing.sh
```

## ✅ Verify Your Setup

### Local Access
- **Immich**: http://localhost:2283
- **Plex**: http://localhost:32400/web

### Remote Access (via Tailscale)
- **Immich**: https://your-macmini.tailnet.ts.net  
- **Plex**: https://your-macmini.tailnet.ts.net:32400
- **Landing Page** *(with reverse proxy)*: https://your-macmini.tailnet.ts.net

### Quick Health Check
```bash
# Check all services
./diagnostics/run_all.sh

# Individual checks
./diagnostics/check_plex_native.sh        # Plex running?
./diagnostics/check_docker_services.sh    # Immich containers healthy?
./diagnostics/check_tailscale.sh          # Tailscale connected?
```

## 🎬 Next Steps: Using Your Server

### Plex Setup
1. Open http://localhost:32400/web
2. Sign in with your Plex account
3. Add media libraries pointing to `/Volumes/warmstore/movies` and `/Volumes/warmstore/tv-shows`
4. Enable hardware transcoding in Settings → Transcoder

> 📖 **Detailed Guide**: [Plex Setup & Usage](PLEX.md)

### Immich Setup  
1. Open http://localhost:2283
2. Create your admin account
3. Download mobile apps and configure server URL
4. Start uploading photos!

> 📖 **Detailed Guide**: [Immich Setup & Usage](IMMICH.md)

### Google Photos Import
```bash
# Import Google Takeout to Immich
./scripts/takeout/enhanced_takeout_import.sh ~/Downloads/takeout-photos.zip
```

> 📖 **Import Guide**: [Google Takeout Import](IMMICH.md#google-takeout-import)

## 🛡️ Security & Best Practices

### Tailscale Network
- Your server is only accessible via your private Tailscale network
- HTTPS encryption for all remote connections
- No open ports to the internet

### Regular Maintenance
```bash
# Check for updates (weekly automatic checks are enabled)
./scripts/automation/check_updates.sh

# Apply updates when ready
./scripts/automation/check_updates.sh   # report only: --apply is disabled until Phase 5 (D11)
```

## 🔧 Common Issues

### Immich Won't Start
```bash
# Check if IMMICH_DB_PASSWORD is set
cat services/immich/.env | grep IMMICH_DB_PASSWORD

# Restart services
cd services/immich && docker compose restart
```

### Storage Arrays Failed
```bash
# Check RAID status
./diagnostics/check_raid_status.sh

# Verify disk IDs
diskutil list
```

### Tailscale Connection Issues
```bash
# Check status
tailscale status

# Reconnect
sudo tailscale down
sudo tailscale up --accept-dns=true
```

## 📚 What's Next?

- **📖 [Detailed Setup Guide](SETUP.md)** - Comprehensive step-by-step setup
- **💾 [Storage Management](STORAGE.md)** - RAID setup, expansion, backups
- **🔒 [Tailscale Setup](TAILSCALE.md)** - Advanced remote access configuration  
- **📊 [Diagnostics](DIAGNOSTICS.md)** - Health monitoring and troubleshooting
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Solutions to common problems

## 💡 Environment Variables Reference

### Required
```bash
IMMICH_DB_PASSWORD=your_secure_password     # In services/immich/.env
```

### Storage (Optional)
```bash
RAID_I_UNDERSTAND_DATA_LOSS=1              # Safety gate for RAID operations
SSD_DISKS="disk4 disk5"                    # SSD disk IDs for warmstore
NVME_DISKS="disk2 disk3"                   # NVMe disk IDs for faststore  
COLD_DISKS="disk6"                         # HDD disk IDs for coldstore
```

### Advanced (Optional)
```bash
IMMICH_SERVER=http://localhost:2283        # For Takeout import
IMMICH_API_KEY=your_api_key               # For Takeout import
```

> 📖 **Full Reference**: [Environment Variables Guide](ENVIRONMENT.md)

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or run diagnostics with `./diagnostics/run_all.sh`.
