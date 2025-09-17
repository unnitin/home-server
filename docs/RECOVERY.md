# 🚨 Recovery Operations Guide

Quick reference for recovering your home server from various failure scenarios.

---

## 🔥 **Emergency Recovery Procedures**

### **Complete System Recovery After Power Outage/Restart**

If your home server is completely down after a power outage or restart:

```bash
# 1. Check system basics
./diagnostics/run_all.sh

# 2. Manual recovery sequence (if automation fails)
./scripts/ensure_storage_mounts.sh           # Recreate mount points
./scripts/21_start_colima.sh                 # Start Docker
./scripts/30_deploy_services.sh              # Start Immich
./scripts/start_plex_safe.sh                 # Start Plex safely
./scripts/37_enable_simple_landing.sh        # Setup landing page

# 3. Verify everything is working
# Replace YOUR-DEVICE.YOUR-TAILNET.ts.net with your actual hostname
# See: https://tailscale.com/kb/1098/machine-names
curl -I https://YOUR-DEVICE.YOUR-TAILNET.ts.net
curl -I https://YOUR-DEVICE.YOUR-TAILNET.ts.net:2283
curl -I https://YOUR-DEVICE.YOUR-TAILNET.ts.net:32400
```

### **Service-Specific Recovery**

#### **Storage Mount Issues**
```bash
# Check current mounts
ls -la /Volumes/

# Recreate mount structure
./scripts/ensure_storage_mounts.sh

# Verify mount points
ls -la /Volumes/warmstore/Movies/
ls -la /Volumes/faststore/
ls -la /Volumes/Archive/
```

#### **Docker/Immich Not Starting**
```bash
# Check Colima status
colima status

# Restart Colima if needed
colima stop && colima start

# Restart Immich services
cd services/immich
docker-compose down
docker-compose up -d

# Check logs
docker-compose logs -f
```

#### **Plex Won't Start (Port Conflicts)**
```bash
# Check what's using port 32400
lsof -i :32400

# If Tailscale is blocking:
sudo tailscale serve --https=32400 off
open -a "Plex Media Server"
# Wait for Plex to start
sudo tailscale serve --bg --https=32400 http://localhost:32400
```

#### **Landing Page Not Working**
```bash
# Kill any existing HTTP servers
pkill -f "python3 -m http.server 8080"

# Restart landing page
./scripts/37_enable_simple_landing.sh

# Check HTTP server
curl -I http://localhost:8080
```

#### **Tailscale HTTPS Not Working**
```bash
# Check Tailscale status
tailscale status

# Check serving configuration
sudo tailscale serve status

# Reset and reconfigure
sudo tailscale serve reset
sudo tailscale serve --bg --https=443 http://localhost:8080
sudo tailscale serve --bg --https=2283 http://localhost:2283
sudo tailscale serve --bg --https=32400 http://localhost:32400
```

---

## 🔧 **LaunchD Service Recovery**

### **Check Service Status**
```bash
# List all homelab services
launchctl list | grep homelab

# Check specific service status
launchctl print gui/$(id -u)/io.homelab.colima
launchctl print gui/$(id -u)/io.homelab.compose.immich
launchctl print gui/$(id -u)/io.homelab.plex
launchctl print gui/$(id -u)/io.homelab.landing
```

### **Restart Failed Services**
```bash
# Restart individual services (all installed services)
launchctl kickstart gui/$(id -u)/io.homelab.storage
launchctl kickstart gui/$(id -u)/io.homelab.colima
launchctl kickstart gui/$(id -u)/io.homelab.compose.immich
launchctl kickstart gui/$(id -u)/io.homelab.plex
launchctl kickstart gui/$(id -u)/io.homelab.landing
launchctl kickstart gui/$(id -u)/io.homelab.tailscale
launchctl kickstart gui/$(id -u)/io.homelab.updatecheck
```

### **Reinstall Automation (If Services Missing)**
```bash
# Remove old services
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/io.homelab.*.plist

# Reinstall enhanced automation
./scripts/40_configure_launchd.sh
```

### **View Service Logs**
```bash
# Check service logs
tail -f /tmp/storage.out
tail -f /tmp/colima.out
tail -f /tmp/immich.out  
tail -f /tmp/plex.out
tail -f /tmp/landing.out

# Check for errors
grep -i error /tmp/*.err
```

---

## 🚨 **Common Failure Scenarios**

### **"Services Start But Can't Access Remotely"**

**Symptoms**: Services run locally but HTTPS URLs don't work

**Solution**:
```bash
# Check Tailscale connection
tailscale status

# Reconnect if down
sudo tailscale up --accept-dns=true

# Reconfigure HTTPS serving
./scripts/37_enable_simple_landing.sh
```

### **"Immich Database Connection Failed"**

**Symptoms**: Immich containers restart repeatedly

**Solution**:
```bash
# Check Immich environment
cat services/immich/.env | grep IMMICH_DB_PASSWORD

# Restart database container specifically
cd services/immich
docker-compose restart immich-postgres
docker-compose restart immich-server
```

### **"Plex Library Empty After Restart"**

**Symptoms**: Plex runs but shows no media

**Solution**:
```bash
# Check storage mounts
ls -la /Volumes/warmstore/Movies/
ls -la /Volumes/warmstore/TV/

# Recreate mounts if missing
./scripts/ensure_storage_mounts.sh

# Restart Plex
pkill -f "Plex Media Server"
open -a "Plex Media Server"
```

### **"Storage Mount Points Missing"**

**Symptoms**: `/Volumes/warmstore`, `/Volumes/faststore` missing

**Solution**:
```bash
# Check warmstore availability
ls -la /Volumes/warmstore/

# If warmstore missing, check RAID status
./diagnostics/check_raid_status.sh

# If warmstore exists, recreate mounts
./scripts/ensure_storage_mounts.sh
```

---

## 📊 **Health Check Commands**

### **Quick Status Check**
```bash
# Overall system health
./diagnostics/run_all.sh

# Service-specific checks
./diagnostics/check_docker_services.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_storage.sh
./diagnostics/check_tailscale.sh
```

### **Manual Service Verification**
```bash
# Test all service URLs (replace YOUR-DEVICE.YOUR-TAILNET.ts.net with your hostname)
# Find your hostname: tailscale status --json | grep '"DNSName"' | head -1 | cut -d'"' -f4 | sed 's/\.$//'
echo "Landing Page: $(curl -s -o /dev/null -w "%{http_code}" https://YOUR-DEVICE.YOUR-TAILNET.ts.net)"
echo "Immich: $(curl -s -o /dev/null -w "%{http_code}" https://YOUR-DEVICE.YOUR-TAILNET.ts.net:2283)"
echo "Plex: $(curl -s -o /dev/null -w "%{http_code}" https://YOUR-DEVICE.YOUR-TAILNET.ts.net:32400)"
```

### **Resource Usage Check**
```bash
# Check system resources
top -l 1 | head -10

# Check storage usage
df -h /Volumes/*

# Check running processes
ps aux | grep -E "(colima|docker|plex|python3.*8080)"
```

---

## 🔄 **Backup & Restore Procedures**

### **Configuration Backup**
```bash
# Backup critical configuration
mkdir -p ~/homeserver-backup/$(date +%Y%m%d)
cp services/immich/.env ~/homeserver-backup/$(date +%Y%m%d)/
cp -r launchd/ ~/homeserver-backup/$(date +%Y%m%d)/
cp ~/.config/colima/default/colima.yaml ~/homeserver-backup/$(date +%Y%m%d)/ 2>/dev/null || true
```

### **Service State Export**
```bash
# Export Tailscale configuration
tailscale status --json > ~/homeserver-backup/$(date +%Y%m%d)/tailscale-status.json

# Export Docker state
cd services/immich && docker-compose config > ~/homeserver-backup/$(date +%Y%m%d)/immich-compose.yml
```

### **Recovery from Backup**
```bash
# Restore configuration (replace YYYYMMDD with backup date)
BACKUP_DATE=20240910
cp ~/homeserver-backup/$BACKUP_DATE/.env services/immich/
cp -r ~/homeserver-backup/$BACKUP_DATE/launchd/ ./

# Reinstall services
./scripts/40_configure_launchd.sh
```

---

## 🆘 **Last Resort Recovery**

If all else fails and you need to start from scratch:

```bash
# 1. Stop all services
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/io.homelab.*.plist
pkill -f "Plex Media Server"
pkill -f "python3 -m http.server"
colima stop

# 2. Clean slate restart
colima delete
rm -rf ~/.colima

# 3. Run setup from scratch (will preserve data on storage)
./setup/setup_full.sh

# 4. Restore your Immich and Plex configuration manually
```

---

## 📞 **Getting Help**

### **Log Collection**
```bash
# Collect all logs for troubleshooting
./diagnostics/collect_logs.sh

# System information
./diagnostics/full_summary.sh
```

### **Key Log Locations**
- **LaunchD Logs**: `/tmp/*.out` and `/tmp/*.err`
- **Colima Logs**: `colima logs`
- **Docker Logs**: `cd services/immich && docker-compose logs`
- **System Logs**: `log show --predicate 'subsystem BEGINSWITH "io.homelab"' --last 1h`

### **Recovery Documentation Links**
- **[Diagnostics Guide](DIAGNOSTICS.md)** - Comprehensive health checking
- **[Automation Guide](AUTOMATION.md)** - LaunchD service management
- **[Storage Guide](STORAGE.md)** - Storage and mount point management
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Detailed problem resolution

---

**Last Updated**: September 10, 2025  
**Recovery Status**: Enhanced automation with graceful recovery procedures
