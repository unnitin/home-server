# 🤖 LaunchD Jobs

System-level service configurations for automatic startup and scheduled tasks.

## 📋 Installed Services

### **io.homelab.colima.plist** - Docker Runtime
Auto-starts Colima VM on system boot to ensure Docker containers are available.

**Service**: Colima Docker runtime  
**Trigger**: System startup  
**Purpose**: Ensures Immich containers start automatically

---

### **io.homelab.compose.immich.plist** - Photo Service
Starts Immich Docker containers after Colima is ready.

**Service**: Immich photo management  
**Trigger**: After Colima startup  
**Purpose**: Auto-start photo backup and management service

---

### **io.homelab.updatecheck.plist** - Maintenance
Weekly automated update checks for all system components.

**Service**: Update checker script  
**Trigger**: Weekly (Sunday 2 AM)  
**Purpose**: Automated maintenance and update notifications

---

### **io.homelab.tailscale.plist** - VPN Service *(Optional)*
Auto-starts Tailscale VPN connection if Tailscale is installed.

**Service**: Tailscale mesh VPN  
**Trigger**: System startup  
**Purpose**: Automatic secure remote access

---

### **io.homelab.powermgmt.plist** - Power Management
Monitors and maintains Mac mini power settings for 24/7 server operation.

**Service**: Power management monitoring  
**Trigger**: System startup + hourly checks  
**Purpose**: Ensures consistent power settings for headless server operation

**Features**:
- Runs `ensure_power_settings.sh` every hour
- Automatically restores server-optimized power settings
- Prevents sleep settings from reverting after system updates
- Logs power management activities to `/Volumes/warmstore/logs/powermgmt/powermgmt.out`

---

### **io.homelab.plex.plist** - Plex Media Server
Auto-starts Plex Media Server for local media streaming.

**Service**: Plex Media Server  
**Trigger**: System startup  
**Purpose**: Local media streaming and management

---

### **io.homelab.jellyfin.plist** - Jellyfin Media Server
Auto-starts Jellyfin Media Server for remote media streaming via Tailscale.

**Service**: Jellyfin Media Server  
**Trigger**: System startup  
**Purpose**: Remote media streaming with Tailscale integration

---

### **io.homelab.media.watcher.plist** - Media Processing Automation
Monitors Staging directories for new media files and automatically processes them according to Plex naming conventions.

**Service**: Media processing watcher  
**Trigger**: System startup (RunAtLoad)  
**Purpose**: Automated media file organization for Plex and Jellyfin Media Servers

**Features**:
- Real-time monitoring of `/Volumes/warmstore/Staging/{Movies,TV Shows,Collections}/`
- Automatic file processing using Plex naming standards
- Preserves folder structure for Collections
- Graceful error handling with failed files moved to staging/failed/
- Comprehensive logging to `/Volumes/warmstore/logs/media-watcher/`
- Uses `fswatch` for real-time monitoring (falls back to polling)
- Background daemon operation with automatic restart on failure

**Supported Formats**: `.mkv`, `.mp4`, `.avi`, `.mov`, `.m4v`, `.wmv`, `.flv`, `.webm`

**Management**:
```bash
# Check watcher status
./scripts/media_watcher.sh status

# Start/stop watcher manually
./scripts/media_watcher.sh start
./scripts/media_watcher.sh stop

# View processing logs
tail -f /Volumes/warmstore/logs/media-watcher/media_processor_*.log
```

---

## 🔧 Management Commands

### Check Service Status
```bash
# List all homelab services
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

# Restart a service
sudo launchctl kickstart system/io.homelab.colima
```

### View Logs
```bash
# System logs for specific service
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h

# General system startup logs
sudo log show --predicate 'messageType == 16' --last 1h
```

---

## 🚀 Installation

### Automated Installation
```bash
sudo ./scripts/40_configure_launchd.sh
```

### Manual Installation
```bash
# Copy plist files
sudo cp launchd/*.plist /Library/LaunchDaemons/

# Set permissions
sudo chown root:wheel /Library/LaunchDaemons/io.homelab.*
sudo chmod 644 /Library/LaunchDaemons/io.homelab.*

# Load services
sudo launchctl load /Library/LaunchDaemons/io.homelab.*
```

---

## 🔧 Troubleshooting

### Service Won't Start
```bash
# Check plist syntax
plutil -lint /Library/LaunchDaemons/io.homelab.colima.plist

# Check file permissions
ls -la /Library/LaunchDaemons/io.homelab.*

# View error logs
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h
```

### Boot Issues
```bash
# Disable problematic service
sudo launchctl unload /Library/LaunchDaemons/io.homelab.colima.plist

# Fix and reload
sudo launchctl load /Library/LaunchDaemons/io.homelab.colima.plist
```

### Service Dependencies
- **Colima** must start before **Immich**
- **Network** must be available for **Tailscale**
- **User session** must exist for some services

---

## 🔗 Related Documentation

- **📖 [Detailed Setup Guide](../docs/SETUP.md#phase-6-automation-setup)** - LaunchD setup walkthrough
- **🔧 [Troubleshooting Guide](../docs/TROUBLESHOOTING.md#emergency-recovery)** - Service recovery procedures
- **🔍 [Diagnostics](../diagnostics/README.md)** - Health checks for services
- **⚙️ [Environment Variables](../docs/ENVIRONMENT.md)** - Service configuration

---

**Service issues?** Check the **🔧 [Troubleshooting Guide](../docs/TROUBLESHOOTING.md)** for recovery procedures.
