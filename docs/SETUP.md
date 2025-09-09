# 📖 Detailed Setup Guide

This comprehensive guide walks you through setting up your Mac mini home server step-by-step, with explanations of what each step does and troubleshooting tips.

## 📋 Overview

You'll set up:
1. **🔧 Bootstrap Environment** - Homebrew and CLI tools
2. **💾 Storage Arrays** *(optional)* - RAID for photos/media/archive
3. **🐳 Docker Runtime** - Colima for containerized services
4. **📸 Immich** - Self-hosted photo management
5. **🎬 Plex** - Native media server
6. **🤖 Automation** - LaunchD for auto-start
7. **🔒 Remote Access** - Tailscale VPN
8. **🌐 Reverse Proxy** *(optional)* - Single URL access

**Total time**: 45-90 minutes (depending on options)

---

## 🔧 Phase 1: Bootstrap Environment (5 minutes)

### What This Does
Installs Homebrew package manager and essential CLI tools safely without modifying system settings or storage.

### Steps

```bash
cd /path/to/home-server
setup/setup.sh
```

**What gets installed**:
- Homebrew (if not present)
- `git`, `curl`, `wget`, `rsync`
- `diskutil`, `mas` (Mac App Store CLI)
- Development tools for building packages

### Verification
```bash
# Check Homebrew
brew --version

# Check essential tools
git --version
curl --version
rsync --version
```

### Troubleshooting
- **Permission denied**: Ensure you have admin privileges
- **Homebrew conflicts**: The script detects existing Homebrew installations
- **Network issues**: Ensure internet connectivity for downloads

---

## 💾 Phase 2: Storage Arrays Setup (15-30 minutes)

> ⚠️ **DESTRUCTIVE OPERATION** - This phase deletes existing data on target disks. **Backup first!**

### Prerequisites

**Identify your disks**:
```bash
diskutil list
```

**Set environment variables**:
```bash
# Required safety gate
export RAID_I_UNDERSTAND_DATA_LOSS=1

# Choose your storage arrays (examples)
export SSD_DISKS="disk4 disk5"          # 2 SSDs for media (warmstore)
export NVME_DISKS="disk2 disk3"         # 2 NVMe for photos (faststore)
export COLD_DISKS="disk6"               # 1 HDD for archive (coldstore)
```

### Option A: Automated Setup

**Rebuild specific arrays**:
```bash
# Rebuild warmstore (SSD array for media)
./scripts/09_rebuild_storage.sh warmstore

# Rebuild faststore (NVMe array for photos)  
./scripts/09_rebuild_storage.sh faststore

# Rebuild coldstore (HDD array for archive)
./scripts/09_rebuild_storage.sh coldstore
```

**Format and mount all arrays**:
```bash
./scripts/12_format_and_mount_raids.sh
```

### Option B: Manual Step-by-Step

**For SSD array (warmstore)**:
```bash
# Create RAID array
./scripts/10_create_raid10_ssd.sh

# Format and mount
./scripts/12_format_and_mount_raids.sh
```

**For NVMe array (faststore)**:
```bash
# Create RAID array
./scripts/11_create_raid10_nvme.sh

# Format and mount  
./scripts/12_format_and_mount_raids.sh
```

**For HDD array (coldstore)**:
```bash
# Create RAID array
./scripts/13_create_raid_coldstore.sh

# Format and mount
./scripts/12_format_and_mount_raids.sh
```

### What Gets Created

| Array Name | Disks | Type | Mount Point | Purpose |
|------------|-------|------|-------------|---------|
| `faststore` | NVMe | 2=mirror, 4=RAID10 | `/Volumes/Photos` | Immich photos (fast) |
| `warmstore` | SSD | 2=mirror, 4=RAID10 | `/Volumes/Media` | Plex media (good speed) |  
| `coldstore` | HDD | 2=mirror, 4=RAID10 | `/Volumes/Archive` | Archive (capacity) |

### Verification
```bash
# Check RAID status
./diagnostics/check_raid_status.sh

# Check mounts  
./diagnostics/verify_media_paths.sh

# Manual check
diskutil list
df -h /Volumes/*
```

### Troubleshooting
- **"Disk already in RAID set"**: Use `export CLEAN_BEFORE_RAID=1` to pre-clean
- **"No such disk"**: Verify disk IDs with `diskutil list`
- **Mount failures**: Check disk permissions and filesystem errors

---

## 🐳 Phase 3: Docker Runtime Setup (5-10 minutes)

### What This Does
Installs and configures Colima (lightweight Docker Desktop alternative) to run Immich containers.

### Steps

**Install Colima and Docker**:
```bash
./scripts/20_install_colima_docker.sh
```

**Start Colima VM**:
```bash
./scripts/21_start_colima.sh
```

### What Gets Installed
- **Colima**: Lightweight Docker runtime for macOS
- **Docker CLI**: Command-line interface
- **Docker Compose**: Multi-container orchestration

### Configuration
Colima starts with:
- **CPU**: 4 cores (or half of available)
- **Memory**: 8GB (or half of available)
- **Disk**: 100GB sparse disk
- **VM Type**: VZ (native Apple Virtualization)

### Verification
```bash
# Check Colima status
colima status

# Check Docker
docker --version
docker ps

# Check Docker Compose
docker compose version
```

### Troubleshooting
- **Permission denied**: Add user to `docker` group (script handles this)
- **VM won't start**: Check available memory and disk space
- **Slow performance**: Consider increasing CPU/memory allocation

---

## 📸 Phase 4: Immich Photo Management (10 minutes)

### What This Does
Deploys Immich (self-hosted Google Photos alternative) with PostgreSQL database, Redis cache, and machine learning features.

### Prerequisites

**Set database password**:
```bash
cd services/immich
cp .env.example .env
${EDITOR:-nano} .env
```

**Edit the `.env` file**:
```bash
IMMICH_DB_PASSWORD=your_secure_password_here
```

### Steps

**Deploy all Immich services**:
```bash
./scripts/30_deploy_services.sh
```

### What Gets Deployed

| Service | Container | Port | Purpose |
|---------|-----------|------|---------|
| Immich Server | `immich-server` | 2283 | Main web application |
| Immich ML | `immich-ml` | - | Machine learning features |
| PostgreSQL | `immich-db` | - | Database with vector extensions |
| Redis | `immich-redis` | - | Cache and session storage |

### Storage Integration
- **Photos**: Stored in `/Volumes/Photos` (faststore array)
- **Database**: Docker volume `immich-db`
- **Cache**: In-memory Redis

### Verification
```bash
# Check all containers
./diagnostics/check_docker_services.sh

# Manual check
cd services/immich && docker compose ps

# Test web access
curl -f http://localhost:2283 || echo "Immich not ready yet"
```

### First-Time Setup
1. Open http://localhost:2283
2. Create admin account
3. Set up mobile apps:
   - **Server URL**: `http://your-local-ip:2283`
   - **For Tailscale**: `https://your-macmini.tailnet.ts.net`

### Troubleshooting
- **Database connection failed**: Check `IMMICH_DB_PASSWORD` in `.env`
- **Containers crash**: Check logs with `docker compose logs`
- **Out of disk space**: Ensure Docker has sufficient disk allocation
- **Slow startup**: ML container takes time to download models

---

## 🎬 Phase 5: Plex Media Server (5 minutes)

### What This Does
Installs Plex Media Server natively (not in Docker) for optimal performance and hardware transcoding support.

### Steps

**Install Plex**:
```bash
./scripts/31_install_native_plex.sh
```

### What Gets Installed
- **Plex Media Server**: Native macOS application
- **Auto-start**: LaunchAgent for automatic startup
- **Hardware Transcoding**: Access to QuickSync/VideoToolbox

### Storage Integration
- **Media Libraries**: Point to `/Volumes/Media` (warmstore array)
- **Metadata**: Stored in `~/Library/Application Support/Plex Media Server`
- **Transcoding**: Temporary files in system temp directory

### Initial Configuration
1. Open http://localhost:32400/web
2. Sign in with Plex account
3. **Add Libraries**:
   - **Movies**: `/Volumes/Media/Movies`
   - **TV Shows**: `/Volumes/Media/TV`
   - **Music**: `/Volumes/Media/Music`
4. **Enable Hardware Transcoding**:
   - Settings → Transcoder
   - Check "Use hardware acceleration when available"

### Verification
```bash
# Check if Plex is running
./diagnostics/check_plex_native.sh

# Manual check
ps aux | grep "Plex Media Server"
lsof -i :32400
```

### Troubleshooting
- **Service not starting**: Check system logs with `Console.app`
- **No hardware transcoding**: Verify codec support on your Mac model
- **Library not scanning**: Check folder permissions on `/Volumes/Media`
- **Remote access issues**: Configure Plex settings for external access

---

## 🤖 Phase 6: Automation Setup (2 minutes)

### What This Does
Configures LaunchD (macOS service manager) to automatically start services on boot and schedule maintenance tasks.

### Steps

**Install LaunchD jobs**:
```bash
sudo ./scripts/40_configure_launchd.sh
```

### What Gets Configured

| Service | File | Purpose |
|---------|------|---------|
| Colima | `io.homelab.colima.plist` | Auto-start Docker runtime |
| Immich | `io.homelab.compose.immich.plist` | Auto-start Immich containers |
| Updates | `io.homelab.updatecheck.plist` | Weekly update checks |
| Tailscale | `io.homelab.tailscale.plist` | Auto-start VPN *(if installed)* |

### Verification
```bash
# Check LaunchD status
sudo launchctl list | grep homelab

# Check specific service
sudo launchctl print system/io.homelab.colima
```

### Manual Control
```bash
# Stop a service
sudo launchctl unload /Library/LaunchDaemons/io.homelab.colima.plist

# Start a service  
sudo launchctl load /Library/LaunchDaemons/io.homelab.colima.plist

# View logs
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h
```

### Troubleshooting
- **Permission denied**: Script requires `sudo` for system LaunchDaemons
- **Service won't start**: Check plist syntax and file permissions
- **Boot issues**: Disable problematic services and check logs

---

## 🔒 Phase 7: Remote Access with Tailscale (10 minutes)

### What This Does
Sets up Tailscale mesh VPN for secure remote access to your services from anywhere in the world.

### Steps

**Install Tailscale**:
```bash
./scripts/90_install_tailscale.sh
```

**Connect to your network**:
```bash
sudo tailscale up --accept-dns=true
```

**Enable HTTPS serving**:
```bash
# Direct service access
sudo tailscale serve --https=443   http://localhost:2283      # Immich
sudo tailscale serve --https=32400 http://localhost:32400      # Plex
```

### What This Provides
- **Encrypted VPN**: All traffic encrypted in transit
- **HTTPS Certificates**: Automatic certificates for your tailnet domain
- **No Port Forwarding**: No router configuration needed
- **Access Control**: Controlled via Tailscale admin console

### Network Access
Your services become available at:
- **Immich**: `https://your-macmini.your-tailnet.ts.net`
- **Plex**: `https://your-macmini.your-tailnet.ts.net:32400`

### Mobile App Configuration
**Immich Mobile**:
- **Server URL**: `https://your-macmini.your-tailnet.ts.net`
- **Username/Password**: From Immich setup

**Plex Mobile**:
- **Server**: Automatically discovered or manual `your-macmini.your-tailnet.ts.net:32400`

### Verification
```bash
# Check Tailscale status
tailscale status

# Check IP and hostname
tailscale ip
tailscale hostname

# Test HTTPS access
curl -k https://$(tailscale hostname).$(tailscale domain)
```

### Troubleshooting
- **Login required**: Complete authentication in browser
- **DNS issues**: Check `--accept-dns=true` was used
- **Certificate errors**: Wait for certificates to provision
- **Mobile connection fails**: Ensure mobile device is on same Tailscale network

---

## 🌐 Phase 8: Reverse Proxy Setup (Optional, 5 minutes)

### What This Does
Sets up Caddy reverse proxy to provide single-URL access to all services via clean paths.

### Steps

**Install Caddy**:
```bash
./scripts/35_install_caddy.sh
```

**Enable reverse proxy**:
```bash
./scripts/36_enable_reverse_proxy.sh
```

### What Gets Configured
- **Caddy Server**: Lightweight web server and proxy
- **Landing Page**: Service dashboard with health indicators
- **Path Routing**: Clean URLs for each service

### URL Structure
- **Homepage**: `https://your-macmini.your-tailnet.ts.net`
- **Immich**: `https://your-macmini.your-tailnet.ts.net/photos`
- **Plex**: `https://your-macmini.your-tailnet.ts.net/plex`

### Landing Page Features
- **Service Status**: Green/red indicators for each service
- **Quick Links**: One-click access to web interfaces
- **System Info**: Basic server information

### Verification
```bash
# Check Caddy status
brew services list | grep caddy

# Test proxy paths
curl -f http://localhost:8443/photos
curl -f http://localhost:8443/plex
```

### Troubleshooting
- **Port conflicts**: Ensure port 8443 is available
- **Proxy errors**: Check service availability and Caddyfile syntax
- **HTTPS issues**: Verify Tailscale serve configuration

---

## ✅ Final Verification

### Health Check Suite
```bash
# Run all diagnostics
./diagnostics/run_all.sh

# Individual checks
./diagnostics/check_raid_status.sh          # Storage arrays
./diagnostics/check_plex_native.sh          # Plex service
./diagnostics/check_docker_services.sh      # Immich containers
./diagnostics/check_tailscale.sh            # VPN connection
./diagnostics/verify_media_paths.sh         # Storage mounts
```

### Service Access Test
**Local access**:
- ✅ Immich: http://localhost:2283
- ✅ Plex: http://localhost:32400/web

**Remote access (via Tailscale)**:
- ✅ Immich: `https://your-macmini.your-tailnet.ts.net`
- ✅ Plex: `https://your-macmini.your-tailnet.ts.net:32400`

**Reverse proxy (if enabled)**:
- ✅ Landing: `https://your-macmini.your-tailnet.ts.net`
- ✅ Photos: `https://your-macmini.your-tailnet.ts.net/photos`
- ✅ Media: `https://your-macmini.your-tailnet.ts.net/plex`

### Performance Verification
```bash
# Check system resources
top -l 1 | head -10
df -h

# Check service performance
docker stats --no-stream
pgrep -f "Plex Media Server" | xargs ps -p
```

---

## 🔄 Maintenance Tasks

### Regular Health Checks
```bash
# Weekly (automated via LaunchD)
./scripts/80_check_updates.sh

# Monthly
./diagnostics/collect_logs.sh
./diagnostics/check_raid_status.sh
```

### Manual Updates
```bash
# Check for updates
./scripts/80_check_updates.sh

# Apply updates when ready
./scripts/80_check_updates.sh --apply
```

### Backup Procedures
```bash
# Backup media to external drive
./scripts/14_backup_store.sh warmstore /Volumes/MyBackup/MediaBackup

# Backup photos
./scripts/14_backup_store.sh faststore /Volumes/MyBackup/PhotoBackup
```

---

## 🎯 What's Next?

### Service-Specific Configuration
- **📸 [Immich Setup & Usage](IMMICH.md)** - Photo management, mobile apps, Google import
- **🎬 [Plex Setup & Usage](PLEX.md)** - Media libraries, transcoding, remote access
- **🔒 [Tailscale Advanced](TAILSCALE.md)** - ACLs, subnet routing, exit nodes

### Advanced Topics
- **💾 [Storage Management](STORAGE.md)** - Expansion, backups, troubleshooting
- **📊 [Diagnostics & Monitoring](DIAGNOSTICS.md)** - Health checks, performance tuning
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

### Optimization
- **🚀 Performance Tuning**: Adjust Docker resources, Plex transcoding
- **📱 Mobile Setup**: Configure apps for optimal remote access
- **🔐 Security Review**: Tailscale ACLs, service isolation

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or run diagnostics to identify issues.
