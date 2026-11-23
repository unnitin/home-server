
# 🔍 Diagnostics Suite

These helper scripts let you quickly verify the health of your home server components.

## 🚀 Quick Health Check

**Run all diagnostics**:
```bash
./diagnostics/run_all.sh
```

## 📋 Individual Diagnostic Scripts

### **check_raid_status.sh** - Storage Health
Shows AppleRAID sets, members, and status for all storage arrays.

```bash
./diagnostics/check_raid_status.sh
```

**Checks**:
- RAID array status (Online, Degraded, Failed)
- Member disk health
- Array capacity and usage

---

### **check_jellyfin.sh** - Jellyfin Service
Confirms Jellyfin is running, port 8096 is open, `/health` reports Healthy, and shows the version and LaunchD job state.

```bash
./diagnostics/check_jellyfin.sh
```

---

### **check_plex_native.sh** - Plex Service
Confirms whether Plex Media Server is running natively and accessible.

```bash
./diagnostics/check_plex_native.sh
```

**Checks**:
- Plex process running
- Web interface accessibility
- LaunchAgent status

---

### **check_docker_services.sh** - Immich Containers
Verifies all Immich Docker containers are healthy and running.

```bash
./diagnostics/check_docker_services.sh
```

**Checks**:
- Container status (running, healthy, restarting)
- Colima VM status
- Docker daemon connectivity

---

### **verify_media_paths.sh** - Storage Mounts
Checks that storage volumes are mounted and accessible with disk usage.

```bash
./diagnostics/verify_media_paths.sh
```

**Checks**:
- `/Volumes/warmstore` (warmstore)
- `/Volumes/faststore` (faststore)  
- `/Volumes/Archive` (coldstore)
- Mount permissions and disk usage

---

### **network_port_check.sh** - Connectivity
Tests whether services are reachable on expected ports.

```bash
./diagnostics/network_port_check.sh [host] [port]

# Examples
./diagnostics/network_port_check.sh localhost 32400  # Plex
./diagnostics/network_port_check.sh localhost 2283   # Immich
./diagnostics/network_port_check.sh localhost 8096   # Jellyfin
```

**Default**: Tests Immich on localhost:2283

---

### **check_power_settings.sh** - Power Management
Validates Mac mini power settings for 24/7 headless server operation.

```bash
./diagnostics/check_power_settings.sh
```

**Checks**:
- System sleep disabled (24/7 availability)
- Display sleep optimized for headless operation
- Disk sleep disabled for immediate access
- Network wake capabilities
- SSD optimizations and power-saving features

### **collect_logs.sh** - Log Collection
Collects system and service logs into a timestamped archive for troubleshooting.

```bash
./diagnostics/collect_logs.sh
```

**Collects**:
- `/tmp/*.out` and `/tmp/*.err` logs
- Service-specific logs
- Creates: `/tmp/homeserver-logs-YYYYMMDD-HHMMSS.tgz`

---

## 🔧 Troubleshooting Integration

### Quick Diagnosis
```bash
# Check everything at once
./diagnostics/run_all.sh

# Focus on specific issues
./diagnostics/check_raid_status.sh      # Storage problems
./diagnostics/check_docker_services.sh  # Immich issues
./diagnostics/check_plex_native.sh      # Plex problems
```

### Performance Monitoring
```bash
# Check system resources
top -l 1 | head -10
df -h /Volumes/*

# Test network connectivity
./diagnostics/network_port_check.sh localhost 2283
./diagnostics/network_port_check.sh localhost 32400
```

### Log Analysis
```bash
# Collect all logs for support
./diagnostics/collect_logs.sh

# Check specific service logs
cd services/immich && docker compose logs
tail -f ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log
```

---

## 🔗 Related Documentation

- **🔧 [Troubleshooting Guide](../docs/TROUBLESHOOTING.md)** - Comprehensive problem-solving
- **💾 [Storage Management](../docs/STORAGE.md)** - RAID health and management
- **🎬 [Plex Setup](../docs/PLEX.md)** - Plex-specific diagnostics
- **📸 [Immich Setup](../docs/IMMICH.md)** - Photo service troubleshooting
- **📖 [Detailed Setup Guide](../docs/SETUP.md)** - Complete system overview

---

**Having issues?** Start with `./diagnostics/run_all.sh` then check the **🔧 [Troubleshooting Guide](../docs/TROUBLESHOOTING.md)** for specific solutions.
