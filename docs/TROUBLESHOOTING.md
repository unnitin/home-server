# 🔧 Troubleshooting Guide

Comprehensive troubleshooting guide for your Mac mini home server setup, covering common issues, diagnostic tools, and recovery procedures.

## 🔍 Quick Diagnostics

### Known Issues & Workarounds

#### Immich Storage Display Bug
**Issue**: Immich web interface shows incorrect storage space (e.g., 476.9 TiB instead of actual 1.9 TiB)

**Root Cause**: This is a [known bug in Immich](https://github.com/immich-app/immich/issues/9514) affecting certain storage configurations

**Solution**: Set a user storage quota in Immich:
1. Go to Immich web interface → Settings (gear icon)
2. Navigate to "User Management"
3. Edit your user account
4. Set a storage quota (e.g., 500GB)
5. Save - this fixes the display issue

**Note**: This is a display bug only - actual storage usage is correct

### Run All Health Checks
```bash
# Comprehensive health check
./diagnostics/run_all.sh

# Individual diagnostics
./diagnostics/check_raid_status.sh          # Storage arrays
./diagnostics/check_plex_native.sh          # Plex service
./diagnostics/check_docker_services.sh      # Immich containers
./diagnostics/verify_media_paths.sh         # Storage mounts
./diagnostics/check_tailscale.sh            # VPN connection
```

### System Status Overview
```bash
# System resources
top -l 1 | head -10
df -h

# Network connectivity
ping -c 3 8.8.8.8
tailscale status

# Service ports
lsof -i :2283    # Immich
lsof -i :32400   # Plex
lsof -i :8080    # Landing page HTTP server
```

---

## 🚨 Emergency Recovery

### Services Won't Start After Reboot

**Check LaunchD services**:
```bash
# List homelab services
launchctl list | grep homelab

# Check specific service status
sudo launchctl print system/io.homelab.colima

# Restart failed services
sudo launchctl unload /Library/LaunchDaemons/io.homelab.colima.plist
sudo launchctl load /Library/LaunchDaemons/io.homelab.colima.plist
```

**Manual service restart**:
```bash
# Start Colima
colima start

# Start Immich
cd services/immich && docker compose up -d

# Start Plex (usually auto-starts)
open -a "Plex Media Server"
```

### Complete System Recovery

**If everything fails**:
```bash
# 1. Stop all services
sudo launchctl unload /Library/LaunchDaemons/io.homelab.*
colima stop

# 2. Restart from clean state
colima delete
colima start

# 3. Redeploy services
./scripts/30_deploy_services.sh

# 4. Restart system services
sudo ./scripts/40_configure_launchd.sh
```

---

## 🐳 Docker & Colima Issues

### Colima Won't Start

**Check status and logs**:
```bash
colima status
colima logs
```

**Common fixes**:
```bash
# Delete and recreate VM
colima delete
colima start

# Check available resources
vm_stat
df -h

# Reset Docker context
docker context use colima
```

### Docker Containers Crashing

**Check container status**:
```bash
cd services/immich
docker compose ps
docker compose logs
```

**Common issues**:

**Out of memory**:
```bash
# Check memory usage
docker stats --no-stream

# Increase Colima memory
colima stop
colima start --memory 8
```

**Database connection failed**:
```bash
# Check environment file
cat services/immich/.env | grep IMMICH_DB_PASSWORD

# Reset database
cd services/immich
docker compose down
docker volume rm immich_immich-db
docker compose up -d
```

**Permission issues**:
```bash
# Fix volume permissions
sudo chown -R $(whoami):staff /Volumes/Photos
chmod -R 755 /Volumes/Photos
```

### Network Issues

**Port conflicts**:
```bash
# Check what's using ports
lsof -i :2283
lsof -i :32400

# Kill conflicting processes
sudo kill -9 <PID>
```

**Docker network problems**:
```bash
# Reset Docker networks
docker network prune -f
cd services/immich && docker compose down && docker compose up -d
```

---

## 💾 Storage Issues

### RAID Arrays Not Mounting

**Check RAID status**:
```bash
./diagnostics/check_raid_status.sh

# Manual check
diskutil list
diskutil appleRAID list
```

**Common fixes**:

**Array degraded**:
```bash
# Check disk health
diskutil info disk4
diskutil verifyVolume /Volumes/Media
```

**Mount issues**:
```bash
# Remount manually
sudo diskutil mount /dev/disk5

# Fix permissions
sudo chown -R $(whoami):staff /Volumes/Media
sudo chmod -R 755 /Volumes/Media
```

**Rebuild required** (⚠️ DESTRUCTIVE):
```bash
export RAID_I_UNDERSTAND_DATA_LOSS=1
export SSD_DISKS="disk4 disk5"

# Backup first!
rsync -av --progress /Volumes/Media/ /Volumes/Backup/MediaBackup/

# Rebuild
./scripts/09_rebuild_storage.sh warmstore
./scripts/12_format_and_mount_raids.sh

# Restore
rsync -av --progress /Volumes/Backup/MediaBackup/ /Volumes/Media/
```

### Disk Space Issues

**Check usage**:
```bash
./diagnostics/verify_media_paths.sh
df -h /Volumes/*
```

**Free up space**:

**Immich cleanup**:
```bash
# Remove duplicates (in Immich web UI)
# Administration → Storage → Duplicate Detection

# Clear thumbnails (will regenerate)
cd services/immich
docker compose exec immich-server rm -rf /photos/.thumbnails
```

**Plex cleanup**:
```bash
# Clear transcoding cache
rm -rf ~/Library/Application\ Support/Plex\ Media\ Server/Cache/Transcode*

# Clear metadata cache
# (Do this from Plex web UI: Settings → Troubleshooting → Clean Bundles)
```

**Docker cleanup**:
```bash
# Remove unused containers/images
docker system prune -a
docker volume prune
```

---

## 📸 Immich Issues

### Immich Web UI Not Loading

**Check services**:
```bash
./diagnostics/check_docker_services.sh
cd services/immich && docker compose ps
```

**Restart services**:
```bash
cd services/immich
docker compose restart
```

**Check logs**:
```bash
docker compose logs immich-server
docker compose logs database
```

### Photo Upload Failures

**Mobile app issues**:
1. **Check server URL**: Ensure correct URL in app
2. **Network connectivity**: Test from same device in browser
3. **Storage space**: Check `/Volumes/Photos` has space
4. **App restart**: Force close and reopen Immich app

**Web upload issues**:
```bash
# Check upload permissions
sudo chown -R $(whoami):staff /Volumes/Photos
chmod -R 755 /Volumes/Photos

# Check container logs
cd services/immich
docker compose logs -f immich-server
```

### Machine Learning Not Working

**Check ML container**:
```bash
cd services/immich
docker compose logs immich-ml

# Restart ML service
docker compose restart immich-ml
```

**Reset ML models**:
```bash
cd services/immich
docker compose down
docker volume rm immich_model-cache
docker compose up -d
```

### Database Issues

**Connection errors**:
```bash
# Verify password in .env
cat services/immich/.env

# Test database connection
cd services/immich
docker compose exec database psql -U postgres -d immich -c "SELECT version();"
```

**Database corruption**:
```bash
# Restore from backup (if available)
cd services/immich
docker compose exec database psql -U postgres immich < backup.sql

# Or reset completely (⚠️ LOSES ALL DATA)
docker compose down -v
docker compose up -d
```

---

## 🎬 Plex Issues

### Plex Service Not Running

**Check process**:
```bash
./diagnostics/check_plex_native.sh
ps aux | grep "Plex Media Server"
```

**Restart Plex**:
```bash
# Stop
sudo pkill -f "Plex Media Server"

# Start
open -a "Plex Media Server"

# Or use LaunchAgent
launchctl unload ~/Library/LaunchAgents/com.plexapp.plexmediaserver.plist
launchctl load ~/Library/LaunchAgents/com.plexapp.plexmediaserver.plist
```

### Remote Access Issues

**Can't access remotely**:
1. **Check Tailscale**: `tailscale status`
2. **Verify HTTPS serving**: `sudo tailscale serve status`
3. **Test local access**: http://localhost:32400/web
4. **Check Plex settings**: Settings → Network → Show Advanced

**Transcoding issues**:
```bash
# Check hardware acceleration
# Plex Settings → Transcoder → Use hardware acceleration

# Monitor transcoding
tail -f ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log | grep Transcode
```

### Library Issues

**Media not scanning**:
1. **Check mount**: `/Volumes/Media` accessible?
2. **Permissions**: Can Plex read the files?
3. **Manual scan**: Settings → Library → Scan Library Files
4. **File naming**: Follow Plex naming conventions

**Metadata issues**:
```bash
# Clear metadata cache
# Plex Settings → Troubleshooting → Clean Bundles

# Refresh library metadata
# Library settings → Refresh All
```

---

## 🔒 Tailscale Issues

### Can't Connect to Tailnet

**Check status**:
```bash
tailscale status
tailscale netcheck
```

**Reconnect**:
```bash
sudo tailscale down
sudo tailscale up --accept-dns=true
```

**Authentication issues**:
```bash
tailscale logout
tailscale up
# Complete browser authentication
```

### Services Not Accessible Remotely

**Check HTTPS serving**:
```bash
sudo tailscale serve status

# Reconfigure serving
sudo tailscale serve --https=443 http://localhost:2283
sudo tailscale serve --https=32400 http://localhost:32400
```

**Certificate issues**:
- Wait 1-2 minutes for initial certificate provisioning
- Try different browser/device
- Check Tailscale admin console for device status

**Network connectivity**:
```bash
# Test from remote device
ping your-macmini.your-tailnet.ts.net
curl -k https://your-macmini.your-tailnet.ts.net
```

### Performance Issues

**Slow connections**:
1. **Check connection type**: Direct vs DERP relay
2. **Network optimization**: Enable UPnP on router
3. **Try different network**: Mobile hotspot vs WiFi

**DNS issues**:
```bash
# Reset DNS
sudo tailscale up --accept-dns=true

# Check DNS resolution
nslookup your-macmini.your-tailnet.ts.net
```

---

## 🌐 Landing Page Issues

### HTTP Server Not Starting

**Check landing page server**:
```bash
# Check if server is running
ps aux | grep "python3 -m http.server 8080"

# Check port availability
lsof -i :8080

# Restart landing page
./scripts/37_enable_simple_landing.sh
```

### HTTPS Access Not Working

**Test individual services**:
```bash
# Test backend services
curl -f http://localhost:2283      # Immich
curl -f http://localhost:32400     # Plex
curl -f http://localhost:8080      # Landing page

# Test HTTPS access
curl -f https://YOUR-DEVICE.YOUR-TAILNET.ts.net
curl -f https://YOUR-DEVICE.YOUR-TAILNET.ts.net:2283
curl -f https://YOUR-DEVICE.YOUR-TAILNET.ts.net:32400
```

**Check Tailscale serving**:
```bash
# Check current serving configuration
sudo tailscale serve status

# Reconfigure if needed
sudo tailscale serve --bg --https=443 http://localhost:8080
sudo tailscale serve --bg --https=2283 http://localhost:2283
sudo tailscale serve --bg --https=32400 http://localhost:32400
```

---

## 🔧 Network Debugging

### Port Conflicts

**Find what's using a port**:
```bash
lsof -i :2283   # Immich
lsof -i :32400  # Plex
lsof -i :8080   # Landing page HTTP server

# Kill conflicting process
sudo kill -9 <PID>
```

### DNS Issues

**Check resolution**:
```bash
# Local resolution
nslookup localhost
dig @8.8.8.8 google.com

# Tailscale DNS
nslookup your-macmini.your-tailnet.ts.net
```

**Reset DNS**:
```bash
# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Firewall Issues

**Check macOS firewall**:
```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Allow specific apps
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add "/Applications/Plex Media Server.app"
```

---

## 📊 Performance Troubleshooting

### High CPU Usage

**Identify processes**:
```bash
top -o cpu
ps aux | sort -nr -k 3 | head -10
```

**Common causes**:
- **Plex transcoding**: Check active streams
- **Immich ML**: Face detection running
- **Docker**: Container resource limits

### High Memory Usage

**Check memory**:
```bash
vm_stat
top -o mem
```

**Docker memory**:
```bash
docker stats --no-stream
```

**Increase Colima memory**:
```bash
colima stop
colima start --memory 8
```

### Disk I/O Issues

**Check disk activity**:
```bash
sudo iotop
df -h
```

**Storage performance**:
```bash
# Test write speed
dd if=/dev/zero of=/Volumes/Photos/test bs=1m count=1000
rm /Volumes/Photos/test

# Check RAID health
./diagnostics/check_raid_status.sh
```

---

## 📝 Log Collection

### Collect All Logs
```bash
./diagnostics/collect_logs.sh
```

### Manual Log Collection

**System logs**:
```bash
# Recent system errors
log show --predicate 'messageType == 16' --last 1h

# Service-specific logs
log show --predicate 'subsystem == "com.plexapp.plexmediaserver"' --last 1h
```

**Service logs**:
```bash
# Docker logs
cd services/immich && docker compose logs > /tmp/immich_logs.txt

# Colima logs
colima logs > /tmp/colima_logs.txt

# Tailscale logs
tailscale debug daemon-logs > /tmp/tailscale_logs.txt
```

**Application logs**:
```bash
# Plex logs
cp ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log /tmp/

# Landing page server logs
cp /tmp/landing-server.out /tmp/ 2>/dev/null || true
```

---

## 🆘 Getting Help

### Before Asking for Help

1. **Run diagnostics**: `./diagnostics/run_all.sh`
2. **Check logs**: Look for error messages
3. **Try restart**: Restart affected services
4. **Document steps**: What were you doing when it failed?

### Information to Gather

**System info**:
```bash
# macOS version
sw_vers

# Hardware info
system_profiler SPHardwareDataType

# Disk info
diskutil list
df -h
```

**Service status**:
```bash
# All health checks
./diagnostics/run_all.sh > /tmp/health_check.txt

# Service versions
docker --version
colima version
tailscale version
```

### Community Resources

- **GitHub Issues**: Check existing issues in the repository
- **Plex Forums**: For Plex-specific problems
- **Immich Discord**: For photo management issues
- **Tailscale Support**: For VPN connectivity problems

---

**Quick fix not working?** Try the comprehensive [📖 Detailed Setup Guide](SETUP.md) to rebuild from scratch, or check specific service guides:
- **🎬 [Plex Troubleshooting](PLEX.md#troubleshooting)**
- **📸 [Immich Troubleshooting](IMMICH.md#troubleshooting)**  
- **🔒 [Tailscale Troubleshooting](TAILSCALE.md#troubleshooting)**
