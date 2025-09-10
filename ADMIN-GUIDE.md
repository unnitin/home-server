# 🔧 Home Media Server - Admin Guide

**Administrative Guide for Server Setup & User Management**

---

## 📋 Admin Overview

As the administrator, you're responsible for:
- **Server Setup & Maintenance** - Initial setup and ongoing maintenance
- **User Access Management** - Inviting users to Tailscale network
- **Service Configuration** - Plex, Immich, and system settings
- **Troubleshooting** - Resolving technical issues

---

## 🌐 Getting Server Information

### Find Your Tailscale Hostname

When users ask "What's the server URL?", run these commands on your Mac mini server:

```bash
# Primary command - gets clean hostname
tailscale status | head -1 | awk '{print $2}'

# Alternative command - JSON output
tailscale status --json | grep '"DNSName"' | cut -d'"' -f4 | sed 's/\.$//'

# Quick status check
tailscale status
```

**Example output:** `mac-mini.tail1a2b3c.ts.net`

**Share with users:**
- **Dashboard:** `https://mac-mini.tail1a2b3c.ts.net`
- **Photos (Immich):** `https://mac-mini.tail1a2b3c.ts.net:2283`
- **Media (Plex):** `https://mac-mini.tail1a2b3c.ts.net:32400`

---

## 👥 User Management

### Adding New Users to Tailscale

#### 1. Invite Users to Network
```bash
# Option 1: Use Tailscale Admin Console (Recommended)
open https://login.tailscale.com/admin/users

# Option 2: Command line invitation
tailscale set --operator=invite user@example.com
```

#### 2. Admin Console Steps
1. **Login:** Go to [Tailscale Admin Console](https://login.tailscale.com/admin/)
2. **Navigate:** Click "Users" → "Invite users"
3. **Add Email:** Enter user's email address
4. **Send:** Click "Send invitation"
5. **Notify User:** Tell them to check their email

#### 3. What Users Receive
- **Email invitation** to join your Tailscale network
- **Link to create account** (if they don't have one)
- **Instructions** to install Tailscale app

### Managing User Access

#### View Network Members
```bash
# See all connected devices
tailscale status

# Detailed network info
tailscale status --json | jq '.Peer[] | {Name: .DNSName, User: .UserID, Online: .Online}'
```

#### Remove User Access
1. **Admin Console:** https://login.tailscale.com/admin/users
2. **Find User:** Locate user in list
3. **Remove:** Click "Remove" or disable access
4. **Confirm:** User will lose access immediately

---

## 🎬 Plex User Management

### Adding Plex Users

#### 1. Create Plex Accounts
- **Option A:** Users create their own free Plex accounts
- **Option B:** Share your Plex Pass (managed users)

#### 2. Share Your Server
```bash
# Get your server info
open http://localhost:32400/web/index.html#!/settings/server

# Share process:
# 1. Settings → Users & Sharing
# 2. "Invite Friend" 
# 3. Enter their email/username
# 4. Choose libraries to share
# 5. Send invitation
```

#### 3. Library Permissions
- **Full Access:** All libraries, admin features
- **Restricted:** Choose specific libraries (Movies, TV, Music)
- **Managed Users:** Child accounts with parental controls

### Plex Server Settings for Sharing

```bash
# Enable remote access (if not done during setup)
# Settings → Remote Access → Enable

# Optimize for sharing:
# Settings → Network → "Treat WAN as LAN" (for Tailscale)
# Settings → Transcoding → Hardware acceleration
```

---

## 📸 Immich User Management

### Creating Immich Accounts

#### 1. Admin Account Setup
- **First user** created during setup becomes admin
- Admin can create additional users

#### 2. Add New Users
1. **Login to Immich:** http://localhost:2283
2. **Admin Panel:** Click user icon → Administration
3. **User Management:** Go to "Users" tab
4. **Create User:** Click "Create user"
5. **Fill Details:** Username, email, password
6. **Set Permissions:** Upload rights, quotas, etc.

#### 3. User Permissions
- **Upload quota** per user
- **Album sharing** permissions
- **Admin privileges** (create/delete users)

### Immich Storage Management

```bash
# Check Immich storage usage
df -h /Volumes/Photos

# View Immich logs
cd services/immich && docker-compose logs immich-server | tail -50

# Backup Immich database
cd services/immich && docker-compose exec database pg_dump -U postgres immich > immich_backup_$(date +%Y%m%d).sql
```

---

## 🔧 System Administration

### Server Health Checks

```bash
# Full system diagnostics
./diagnostics/run_all.sh

# Check individual components
./diagnostics/check_colima_docker.sh
./diagnostics/check_immich.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_tailscale.sh
./diagnostics/check_raid_status.sh

# Storage monitoring
df -h /Volumes/*
du -sh /Volumes/Media/* | sort -hr
du -sh /Volumes/Photos/* | sort -hr
```

### Service Management

```bash
# Restart Immich
cd services/immich && docker-compose restart

# Restart Plex
sudo pkill -f "Plex Media Server"
open -a "Plex Media Server"

# Restart Tailscale
sudo tailscale down && sudo tailscale up --accept-dns=true

# Check service status
./diagnostics/check_docker_services.sh
```

### Update Management

```bash
# Check for updates
./scripts/80_check_updates.sh

# Update Homebrew packages
brew update && brew upgrade

# Update Immich
cd services/immich && docker-compose pull && docker-compose up -d

# Update Plex (check App Store or Plex website)
```

---

## 💾 Backup & Maintenance

### Regular Backup Tasks

```bash
# Backup media storage
./scripts/14_backup_store.sh warmstore /Volumes/Backup/MediaBackup

# Backup photo storage  
./scripts/14_backup_store.sh faststore /Volumes/Backup/PhotoBackup

# Backup Immich database
cd services/immich
docker-compose exec database pg_dump -U postgres immich > /Volumes/Backup/immich_db_$(date +%Y%m%d).sql
```

### Storage Management

```bash
# Check RAID health
diskutil appleRAID list
./diagnostics/check_raid_status.sh

# Monitor disk usage
df -h
du -sh /Volumes/*/

# Clean up old files
# (Be careful - verify before deleting)
find /Volumes/Media -name "*.tmp" -delete
find /tmp -name "*homelab*" -mtime +7 -delete
```

### Log Management

```bash
# View system logs
./diagnostics/collect_logs.sh

# Immich logs
cd services/immich && docker-compose logs --tail=100

# Plex logs (if needed)
tail -f ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log
```

---

## 🚨 Troubleshooting

### Common Admin Tasks

#### User Can't Connect
1. **Verify Tailscale invitation sent**
2. **Check network status:** `tailscale status`
3. **Confirm user accepted invitation**
4. **Test server accessibility:** `curl -I https://$(tailscale status | head -1 | awk '{print $2}'):2283`

#### Services Down
```bash
# Quick health check
./diagnostics/run_all.sh | grep -E "(FAIL|ERROR|❌)"

# Restart all services
sudo launchctl unload ~/Library/LaunchAgents/io.homelab.*
sudo launchctl load ~/Library/LaunchAgents/io.homelab.*
```

#### Storage Issues
```bash
# Check RAID status
diskutil appleRAID list | grep -E "(Status|Size)"

# Check mount points
mount | grep -E "(Media|Photos|Archive)"

# Remount if needed
sudo diskutil mount /dev/disk5s1
```

#### Performance Issues
```bash
# Check system resources
top -l 1 | head -20

# Check Docker resources
docker stats

# Monitor network
netstat -i
```

---

## ⚙️ Advanced Configuration

### Customizing Services

#### Immich Configuration
```bash
# Edit Immich settings
cd services/immich
cp .env.example .env
# Edit .env file for custom settings

# Advanced Docker settings
# Edit docker-compose.yml for resource limits
```

#### Tailscale Advanced Settings
```bash
# Enable exit node (optional)
sudo tailscale up --advertise-exit-node

# Custom DNS
sudo tailscale up --accept-dns=false

# SSH access
sudo tailscale up --ssh
```

### Security Hardening

```bash
# Check Tailscale ACLs
# Go to: https://login.tailscale.com/admin/acls

# Monitor failed login attempts
# Check Immich and Plex logs for unauthorized access

# Update system regularly
sudo softwareupdate -ia
brew update && brew upgrade
```

---

## 📞 Getting Help

### Admin Resources

- **Tailscale Admin Console:** https://login.tailscale.com/admin/
- **Plex Server Settings:** http://localhost:32400/web/#!/settings
- **Immich Admin Panel:** http://localhost:2283 (login as admin)

### Documentation Links

- **Tailscale KB:** https://tailscale.com/kb/
- **Plex Support:** https://support.plex.tv/
- **Immich Docs:** https://immich.app/docs/administration/

### Emergency Commands

```bash
# Stop all services
sudo launchctl unload ~/Library/LaunchAgents/io.homelab.*
cd services/immich && docker-compose down

# Start all services
sudo launchctl load ~/Library/LaunchAgents/io.homelab.*
cd services/immich && docker-compose up -d

# Reset Tailscale
sudo tailscale logout
sudo tailscale up --accept-dns=true

# Factory reset (DESTRUCTIVE - backup first!)
# This is for complete rebuilds only
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore
```

---

**🎯 Remember:** Always backup before making major changes, and test with one user before rolling out to everyone!
