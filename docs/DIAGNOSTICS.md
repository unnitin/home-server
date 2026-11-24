# 📊 Diagnostics & Monitoring Guide

Comprehensive guide for monitoring, diagnosing, and troubleshooting your Mac mini home server health.

## 📋 Overview

The diagnostics suite provides:
- **🔍 Health monitoring** for all server components
- **📊 Performance metrics** and resource usage
- **🚨 Early warning system** for potential issues
- **📝 Log collection** for troubleshooting
- **🔧 Guided troubleshooting** with specific recommendations

---

## 🚀 Quick Health Check

### Run All Diagnostics
```bash
# Comprehensive health check (recommended)
./diagnostics/run_all.sh

# Quick summary only
./diagnostics/full_summary.sh
```

**What it checks**:
- ✅ Prerequisites & dependencies
- ✅ Storage arrays & mount points  
- ✅ Docker containers & services
- ✅ Plex Media Server
- ✅ Network connectivity
- ✅ Tailscale VPN
- ✅ LaunchD automation
- ✅ System integration

### Output Example
```
🔍 Hakuna Mateti HomeServer - Comprehensive Diagnostics
========================================================

== Core System Health ==
✅ Prerequisites & Dependencies
✅ Homebrew Package Manager

== Storage & RAID ==
✅ RAID Array Status
⚠️  Storage Health (1 warning)
✅ Mount Points & Paths

== Application Services ==
✅ Immich Photo Service
❌ Plex Media Server (not running)

Results: 8 passed, 1 warnings, 1 failed
🚨 Issues found - check failed components
```

---

## 📋 Individual Diagnostic Scripts

### **Core System Checks**

#### `check_prereqs.sh` - Prerequisites & Dependencies
Verifies essential tools and system requirements.

```bash
./diagnostics/check_prereqs.sh
```

**Checks**:
- Shell version and features
- Git, Python, Xcode CLI tools
- File permissions and quarantine
- Basic system utilities

#### `check_homebrew.sh` - Package Manager
Validates Homebrew installation and health.

```bash
./diagnostics/check_homebrew.sh
```

**Checks**:
- Homebrew presence and version
- `brew doctor` status
- Write permissions
- Essential packages

---

### **Storage & RAID Checks**

#### `check_raid_status.sh` - RAID Array Health
Comprehensive RAID monitoring with detailed status.

```bash
./diagnostics/check_raid_status.sh
```

**Enhanced features**:
- RAID set status (Online, Degraded, Failed)
- Individual disk health
- Mount point verification
- Disk usage warnings (>80%, >90%)
- Failure detection and recommendations

#### `check_storage.sh` - Storage Health
Basic storage checks for all tiers.

```bash
./diagnostics/check_storage.sh
```

#### `verify_media_paths.sh` - Mount Points
Detailed analysis of storage mount points.

```bash
./diagnostics/verify_media_paths.sh
```

**Advanced features**:
- Mount validation per storage tier
- Disk usage analysis with thresholds
- Write permission verification
- Content detection
- Storage architecture summary

---

### **Container & Service Checks**

#### `check_colima_docker.sh` - Docker Runtime
Docker and Colima health verification.

```bash
./diagnostics/check_colima_docker.sh
```

**Checks**:
- Colima status and version
- Docker daemon connectivity
- Container runtime health
- Compose plugin availability

#### `check_docker_services.sh` - Immich Containers
Container health for photo management service.

```bash
./diagnostics/check_docker_services.sh
```

#### `check_immich.sh` - Photo Service
Comprehensive Immich service validation.

```bash
./diagnostics/check_immich.sh
```

**Checks**:
- Configuration file presence
- HTTP service availability
- Database connectivity
- API responsiveness

---

### **Application Service Checks**

#### `check_jellyfin.sh` - Jellyfin Media Server
Process, port 8096, the `/health` endpoint, version, and the `io.homelab.jellyfin` LaunchD job.

```bash
./diagnostics/check_jellyfin.sh
```

#### `check_plex_native.sh` - Plex Media Server
Enhanced Plex monitoring with detailed diagnostics.

```bash
./diagnostics/check_plex_native.sh
```

**Enhanced features**:
- Process detection and details
- Web interface accessibility
- LaunchAgent status verification
- Configuration validation
- Media directory availability
- Performance indicators

---

### **Network & Remote Access**

#### `check_tailscale.sh` - VPN Service
Tailscale connection and configuration validation.

```bash
./diagnostics/check_tailscale.sh
```

**Checks**:
- Tailscale CLI (found on PATH or inside the Tailscale Mac app)
- Connection status
- IP assignment

#### `check_remote_access.sh` - Tailnet HTTPS (tailscale serve)
Compares the live `tailscale serve` mappings with `config/tailscale_serve.txt` and checks that Funnel (public internet access) is off. Replaces the old Caddy check; Caddy is no longer part of the setup.

```bash
./diagnostics/check_remote_access.sh
```

To fix missing or wrong mappings: `scripts/infrastructure/apply_tailscale_serve.sh` (add `--dry-run` to preview).

#### `network_port_check.sh` - Port Connectivity
Enhanced network connectivity testing.

```bash
./diagnostics/network_port_check.sh [host] [port]

# Examples with service detection
./diagnostics/network_port_check.sh localhost 2283   # Immich
./diagnostics/network_port_check.sh localhost 32400  # Plex
./diagnostics/network_port_check.sh localhost 8096   # Jellyfin
```

**Enhanced features**:
- Automatic service detection by port
- HTTP/HTTPS response testing
- Troubleshooting suggestions
- Performance timing

---

### **System Integration**

#### `check_launchd.sh` - Automation Services
LaunchD service status and health.

```bash
./diagnostics/check_launchd.sh
```

**Checks**:
- Service loading status
- Dependency verification
- Error detection
- Performance monitoring

---

## 📝 Log Collection

### `collect_logs.sh` - Comprehensive Log Gathering
Enhanced log collection for troubleshooting support.

```bash
./diagnostics/collect_logs.sh
```

**Improved features**:
- **System information**: Hardware, OS version, processes
- **Service logs**: Docker, Plex, Tailscale (including `tailscale serve` mappings)
- **Configuration files**: Sanitized for privacy
- **Recent error logs**: System and application errors
- **Performance data**: Resource usage and metrics
- **Compressed archive**: Timestamped .tgz file

**Output**:
```
Archive: /tmp/homeserver-logs-20250909-124530.tgz
Archive size: 2.3M

💡 Usage:
   - Review logs: tar -tzf /tmp/homeserver-logs-20250909-124530.tgz
   - Extract: tar -xzf /tmp/homeserver-logs-20250909-124530.tgz
   - Send for support: Upload the .tgz file
```

---

## 🔧 Advanced Monitoring

### Performance Monitoring

**Real-time system monitoring**:
```bash
# CPU and memory usage
top -l 1 | head -20

# Disk I/O monitoring
sudo iotop -C

# Network monitoring
nettop -d

# Docker container resources
docker stats --no-stream
```

**Storage performance testing**:
```bash
# Write speed test
dd if=/dev/zero of=/Volumes/Photos/test_file bs=1m count=1000
rm /Volumes/Photos/test_file

# Read speed test (use existing large file)
dd if=/Volumes/Photos/large_file of=/dev/null bs=1m
```

### Automated Monitoring

**Set up periodic health checks**:
```bash
# Add to crontab for regular monitoring
# Check every hour and log results
0 * * * * /path/to/diagnostics/run_all.sh >> /tmp/health_check.log 2>&1

# Weekly comprehensive check with log collection
0 2 * * 0 /path/to/diagnostics/collect_logs.sh
```

**Health check alerts** (example script):
```bash
#!/bin/bash
# health_alert.sh - Alert on failures

if ! ./diagnostics/run_all.sh > /tmp/health_check_result.txt 2>&1; then
    # Send notification (macOS)
    osascript -e 'display notification "HomeServer health check failed" with title "Server Alert"'
    
    # Or send email (if configured)
    # mail -s "HomeServer Alert" admin@example.com < /tmp/health_check_result.txt
fi
```

---

## 📊 Health Monitoring Dashboard

### Quick Status Overview
```bash
# One-line health summary
./diagnostics/run_all.sh 2>/dev/null | grep "Results:" | tail -1
```

### Service Status Matrix
```bash
# Check all critical services
for service in "check_raid_status" "check_plex_native" "check_docker_services" "check_tailscale"; do
    echo -n "$service: "
    if ./diagnostics/${service}.sh >/dev/null 2>&1; then
        echo "✅"
    else
        echo "❌"
    fi
done
```

### Resource Usage Summary
```bash
# Disk usage across all storage tiers
echo "Storage Usage:"
df -h /Volumes/* 2>/dev/null | grep -E "(Media|Photos|Archive)" | while read line; do
    echo "  $line"
done

# Container resource usage
echo -e "\nContainer Resources:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
```

---

## 🚨 Alert Thresholds & Responses

### Critical Alerts (Immediate Action Required)
- **Storage >95% full**: Immediate cleanup needed
- **RAID degraded/failed**: Hardware replacement needed
- **All services down**: System restart required
- **Network unreachable**: Connectivity issue

### Warning Alerts (Monitor Closely)
- **Storage >80% full**: Plan expansion
- **High CPU usage**: Check transcoding load
- **Container restarts**: Investigate logs
- **Network latency**: Check connection quality

### Info Alerts (Routine Monitoring)
- **Update available**: Schedule maintenance
- **Log rotation needed**: Cleanup old logs
- **Performance metrics**: Trend analysis

---

## 🔧 Troubleshooting Integration

### Diagnostic-Driven Troubleshooting

**1. Identify the issue**:
```bash
./diagnostics/run_all.sh
```

**2. Focus on failed component**:
```bash
# If Plex fails
./diagnostics/check_plex_native.sh

# If storage issues
./diagnostics/check_raid_status.sh
./diagnostics/verify_media_paths.sh
```

**3. Collect detailed information**:
```bash
./diagnostics/collect_logs.sh
```

**4. Apply targeted fixes**: See [Troubleshooting Guide](TROUBLESHOOTING.md)

### Common Diagnostic Patterns

**Service startup issues**:
```bash
# Check dependencies first
./diagnostics/check_prereqs.sh
./diagnostics/check_homebrew.sh

# Then check specific service
./diagnostics/check_docker_services.sh  # For Immich
./diagnostics/check_plex_native.sh      # For Plex
```

**Storage problems**:
```bash
# Complete storage health check
./diagnostics/check_raid_status.sh
./diagnostics/check_storage.sh
./diagnostics/verify_media_paths.sh
```

**Network connectivity**:
```bash
# Test all critical ports
./diagnostics/network_port_check.sh localhost 2283
./diagnostics/network_port_check.sh localhost 32400
./diagnostics/check_tailscale.sh
```

---

## 🔗 Related Documentation

- **🔧 [Troubleshooting Guide](TROUBLESHOOTING.md)** - Problem-solving procedures
- **📖 [Detailed Setup Guide](SETUP.md)** - System component overview  
- **💾 [Storage Management](STORAGE.md)** - RAID health and management
- **🎬 [Plex Setup](PLEX.md)** - Media server specific diagnostics
- **📸 [Immich Setup](IMMICH.md)** - Photo service troubleshooting
- **🔒 [Tailscale Setup](TAILSCALE.md)** - VPN connectivity diagnostics

---

**Having issues?** Start with `./diagnostics/run_all.sh` to identify problems, then check the specific component guides above for detailed troubleshooting steps.
