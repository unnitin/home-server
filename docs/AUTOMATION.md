# 🤖 Automation & LaunchD Guide

Complete guide for setting up automated services, scheduled tasks, and system maintenance on your Mac mini home server.

## 📋 Overview

Automation includes:
- **🚀 Auto-start services**: Boot-time startup of essential services
- **📅 Scheduled maintenance**: Weekly update checks and cleanup
- **🔄 Service management**: Dependency handling and health monitoring
- **🛡️ Error recovery**: Automatic restart on failures

---

## 🚀 Auto-Start Services

### LaunchD Configuration

**Install all automation**:
```bash
sudo ./scripts/40_configure_launchd.sh
```

### Service Hierarchy

```mermaid
graph TD
    A[System Boot] --> B[Colima Docker]
    B --> C[Immich Containers]
    A --> D[Tailscale VPN]
    A --> E[Update Scheduler]
```

**Boot sequence**:
1. **System startup** triggers LaunchDaemons
2. **Colima** starts Docker runtime
3. **Immich** containers start after Docker ready
4. **Tailscale** connects VPN (if configured)
5. **Update checker** schedules weekly maintenance

---

## 📋 Installed Services

### **io.homelab.colima.plist** - Docker Runtime

**Purpose**: Ensures Docker/Colima starts automatically on boot

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.homelab.colima</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
```

**Management**:
```bash
# Check status
sudo launchctl print system/io.homelab.colima

# Restart
sudo launchctl kickstart system/io.homelab.colima

# Stop
sudo launchctl unload /Library/LaunchDaemons/io.homelab.colima.plist
```

---

### **io.homelab.compose.immich.plist** - Photo Service

**Purpose**: Auto-starts Immich containers after Colima is ready

**Dependencies**:
- Requires Colima to be running
- Waits for Docker socket availability
- Monitors container health

**Management**:
```bash
# Check Immich service status
sudo launchctl print system/io.homelab.compose.immich

# Manual restart
cd services/immich && docker compose restart
```

---

### **io.homelab.updatecheck.plist** - Maintenance

**Purpose**: Weekly automated update checks

**Schedule**: Every Sunday at 2:00 AM
```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Weekday</key>
    <integer>0</integer>
    <key>Hour</key>
    <integer>2</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

**What it does**:
- Checks for Homebrew updates
- Checks for Docker image updates  
- Checks for macOS updates
- Generates update report
- Logs results to `/tmp/update-check.log`

**Manual execution**:
```bash
./scripts/80_check_updates.sh
./scripts/80_check_updates.sh --apply  # Apply updates
```

---

### **io.homelab.tailscale.plist** - VPN Service *(Optional)*

**Purpose**: Auto-starts Tailscale VPN connection

**Conditions**:
- Only installed if Tailscale is present
- Waits for network connectivity
- Preserves previous connection settings

**Management**:
```bash
# Check Tailscale status
tailscale status

# Manual control
sudo tailscale up --accept-dns=true
sudo tailscale down
```

---

## 🔧 Service Management

### Health Monitoring

**Check all services**:
```bash
# List homelab services
sudo launchctl list | grep homelab

# Detailed status
sudo launchctl print system/io.homelab.colima
sudo launchctl print system/io.homelab.compose.immich
```

**Service logs**:
```bash
# View service logs
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h

# Real-time monitoring
sudo log stream --predicate 'subsystem BEGINSWITH "io.homelab"'
```

### Manual Control

**Start/stop individual services**:
```bash
# Stop service
sudo launchctl unload /Library/LaunchDaemons/io.homelab.colima.plist

# Start service
sudo launchctl load /Library/LaunchDaemons/io.homelab.colima.plist

# Restart service
sudo launchctl kickstart system/io.homelab.colima
```

**Emergency stop all**:
```bash
sudo launchctl unload /Library/LaunchDaemons/io.homelab.*
```

### Dependency Management

**Service dependencies**:
```bash
# Colima must be running for Immich
sudo launchctl print system/io.homelab.colima | grep State

# Check Docker availability before starting Immich
docker ps > /dev/null 2>&1 && echo "Docker ready"
```

---

## 📅 Scheduled Maintenance

### Update Checking

**Automated weekly checks**:
- **Schedule**: Sunday 2 AM
- **Scope**: Homebrew, Docker images, macOS
- **Output**: `/tmp/update-check.log`
- **Action**: Check only (manual apply)

**Manual update process**:
```bash
# Check for updates
./scripts/80_check_updates.sh

# Review available updates
cat /tmp/update-check.log

# Apply updates when ready
./scripts/80_check_updates.sh --apply
```

### Custom Maintenance Tasks

**Add custom scheduled task**:

1. **Create script** (`scripts/custom_maintenance.sh`):
```bash
#!/bin/bash
# Custom maintenance script
echo "$(date): Running custom maintenance" >> /tmp/custom_maintenance.log

# Your maintenance tasks here
./diagnostics/check_raid_status.sh >> /tmp/custom_maintenance.log
```

2. **Create LaunchD plist** (`launchd/io.homelab.custom.plist`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.homelab.custom</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/scripts/custom_maintenance.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

3. **Install**:
```bash
sudo cp launchd/io.homelab.custom.plist /Library/LaunchDaemons/
sudo launchctl load /Library/LaunchDaemons/io.homelab.custom.plist
```

---

## 🔄 Error Recovery

### Automatic Restart

**KeepAlive configuration**:
```xml
<key>KeepAlive</key>
<dict>
    <key>SuccessfulExit</key>
    <false/>
    <key>NetworkState</key>
    <true/>
</dict>
```

**Behavior**:
- Restart on unexpected exit
- Wait for network availability
- Limit restart attempts

### Manual Recovery

**Service crashed**:
```bash
# Check what happened
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h

# Restart service
sudo launchctl kickstart system/io.homelab.colima
```

**Complete reset**:
```bash
# Stop all services
sudo launchctl unload /Library/LaunchDaemons/io.homelab.*

# Clean restart
colima delete && colima start
cd services/immich && docker compose up -d

# Reload services
sudo launchctl load /Library/LaunchDaemons/io.homelab.*
```

---

## 🔍 Monitoring & Logging

### Log Locations

**System logs**:
```bash
# LaunchD logs
sudo log show --predicate 'subsystem BEGINSWITH "io.homelab"'

# Service-specific logs
sudo log show --predicate 'subsystem == "io.homelab.colima"' --last 1h
```

**Application logs**:
```bash
# Colima logs
colima logs

# Docker logs
cd services/immich && docker compose logs

# Update check logs
cat /tmp/update-check.log
```

### Performance Monitoring

**Resource usage**:
```bash
# Check system load
top -l 1 | head -10

# Service resource usage
ps aux | grep -E "(colima|docker|immich)"

# Disk usage
df -h /Volumes/*
```

**Service health**:
```bash
# Quick health check
./diagnostics/run_all.sh

# Specific service checks
./diagnostics/check_docker_services.sh
./diagnostics/check_plex_native.sh
```

---

## 🛠️ Advanced Configuration

### Service Priorities

**Start order control**:
```xml
<!-- High priority (starts first) -->
<key>ProcessType</key>
<string>Background</string>
<key>Nice</key>
<integer>-10</integer>

<!-- Low priority (starts last) -->
<key>Nice</key>
<integer>10</integer>
```

### Resource Limits

**Memory and CPU limits**:
```xml
<key>HardResourceLimits</key>
<dict>
    <key>MemoryLimit</key>
    <integer>2147483648</integer>  <!-- 2GB in bytes -->
    <key>NumberOfFiles</key>
    <integer>1024</integer>
</dict>
```

### Environment Variables

**Pass environment to services**:
```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key>
    <string>/Users/username</string>
</dict>
```

---

## 🔧 Troubleshooting

### Service Won't Start

**Check plist syntax**:
```bash
plutil -lint /Library/LaunchDaemons/io.homelab.colima.plist
```

**Check permissions**:
```bash
ls -la /Library/LaunchDaemons/io.homelab.*
# Should be: -rw-r--r--  1 root  wheel
```

**Check dependencies**:
```bash
# Ensure required binaries exist
which colima docker docker-compose
```

### Boot Issues

**Disable problematic service**:
```bash
sudo launchctl unload /Library/LaunchDaemons/io.homelab.problematic.plist
```

**Debug boot process**:
```bash
# View boot logs
sudo log show --predicate 'messageType == 16' --start "$(date -j -v-10M '+%Y-%m-%d %H:%M:%S')"
```

### Performance Issues

**High CPU usage**:
```bash
# Identify resource-heavy services
top -o cpu | head -20

# Adjust service priority
# Edit plist and add <key>Nice</key><integer>10</integer>
```

**Memory issues**:
```bash
# Check memory usage
vm_stat

# Add memory limits to plist
# Use HardResourceLimits as shown above
```

---

## 🔗 Related Documentation

- **📖 [Detailed Setup Guide](SETUP.md#phase-6-automation-setup)** - Initial automation setup
- **🤖 [LaunchD Jobs](../launchd/README.md)** - Service configuration details
- **🔧 [Troubleshooting Guide](TROUBLESHOOTING.md#emergency-recovery)** - Service recovery procedures
- **🔍 [Diagnostics](../diagnostics/README.md)** - Health monitoring tools
- **⚙️ [Environment Variables](ENVIRONMENT.md)** - Configuration reference

---

**Service automation issues?** Check the **🔧 [Troubleshooting Guide](TROUBLESHOOTING.md)** for recovery procedures and detailed debugging steps.
