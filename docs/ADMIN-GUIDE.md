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

**Example output:** `homeserver.tail9x8y7z.ts.net`

**Share with users:**
- **Dashboard:** `https://homeserver.tail9x8y7z.ts.net`
- **Photos (Immich):** `https://homeserver.tail9x8y7z.ts.net:2283`
- **Media (Plex):** `https://homeserver.tail9x8y7z.ts.net:32400`

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

## 💾 Storage Organization & Management

### Understanding Mount Points

After RAID setup, you have three primary storage locations:

| Mount Point | Purpose | RAID Type | Usage |
|-------------|---------|-----------|--------|
| `/Volumes/warmstore` | Plex media library | SSD Mirror/RAID10 | Movies, TV Shows, Music |
| `/Volumes/faststore` | Immich photo storage | NVMe Mirror/RAID10 | Photos, videos, albums |
| `/Volumes/Archive` | Long-term storage | HDD Single/Mirror | Backups, archives, old files |

### Ideal Folder Structure

#### 📹 Media Storage (`/Volumes/warmstore`)

**For Plex to work optimally, organize content like this:**

```bash
/Volumes/warmstore/
├── Movies/
│   ├── The Matrix (1999)/
│   │   ├── The Matrix (1999).mkv
│   │   └── The Matrix (1999)-trailer.mp4
│   ├── Inception (2010)/
│   │   ├── Inception (2010).mp4
│   │   └── poster.jpg
│   └── Top Gun Maverick (2022)/
│       ├── Top Gun Maverick (2022).mkv
│       └── Top Gun Maverick (2022)-behind-the-scenes.mkv
├── TV Shows/
│   ├── Breaking Bad/
│   │   ├── Season 01/
│   │   │   ├── Breaking Bad - S01E01 - Pilot.mkv
│   │   │   ├── Breaking Bad - S01E02 - Cat's in the Bag.mkv
│   │   │   └── ...
│   │   ├── Season 02/
│   │   └── Season 03/
│   ├── The Office (US)/
│   │   ├── Season 01/
│   │   ├── Season 02/
│   │   └── ...
│   └── Stranger Things/
│       ├── Season 01/
│       ├── Season 02/
│       └── Season 03/
├── Music/
│   ├── Artist Name/
│   │   ├── Album Name (Year)/
│   │   │   ├── 01 - Track Name.mp3
│   │   │   ├── 02 - Track Name.mp3
│   │   │   └── cover.jpg
│   │   └── Another Album (Year)/
│   └── Various Artists/
└── Collections/
    ├── Marvel Cinematic Universe/
    ├── James Bond Collection/
    └── Studio Ghibli/
```

#### 📸 Photo Storage (`/Volumes/faststore`)

**Immich manages this automatically, but you can also manually organize:**

```bash
/Volumes/faststore/
├── library/                 # Immich managed files
│   ├── upload/
│   ├── thumbs/
│   └── encoded-video/
├── import/                  # Manual import staging
│   ├── Google Takeout/
│   ├── Old iPhone Backup/
│   └── Camera SD Cards/
└── backup/                  # Manual backups
    ├── 2023/
    ├── 2024/
    └── 2025/
```

#### 🗄️ Archive Storage (`/Volumes/Archive`)

**Long-term storage and backups:**

```bash
/Volumes/Archive/
├── Media Backups/
│   ├── Old Movie Collection/
│   ├── TV Show Archive/
│   └── Music Archive/
├── Photo Backups/
│   ├── Pre-Immich Photos/
│   ├── Family Archives/
│   └── Raw Photo Backups/
├── System Backups/
│   ├── Mac Backups/
│   ├── Configuration Backups/
│   └── Database Dumps/
└── Documents/
    ├── Important Files/
    ├── Old Projects/
    └── Reference Materials/
```

### Setting Up Media Organization

#### 1. Create Initial Directory Structure

```bash
# Create Movies structure
sudo mkdir -p "/Volumes/warmstore/Movies"
sudo mkdir -p "/Volumes/warmstore/TV Shows"
sudo mkdir -p "/Volumes/warmstore/Music"
sudo mkdir -p "/Volumes/warmstore/Collections"

# Create staging areas
sudo mkdir -p "/Volumes/warmstore/New Uploads"
sudo mkdir -p "/Volumes/warmstore/To Process"

# Set permissions
sudo chown -R $(whoami):staff "/Volumes/warmstore"
sudo chmod -R 755 "/Volumes/warmstore"
```

#### 2. Create Photo Import Structure

```bash
# Create photo organization folders
sudo mkdir -p "/Volumes/faststore/import"
sudo mkdir -p "/Volumes/faststore/backup"

# Set permissions for Immich
sudo chown -R $(whoami):staff "/Volumes/faststore"
sudo chmod -R 755 "/Volumes/faststore"
```

#### 3. Create Archive Structure

```bash
# Create archive organization
sudo mkdir -p "/Volumes/Archive/Media Backups"
sudo mkdir -p "/Volumes/Archive/Photo Backups"
sudo mkdir -p "/Volumes/Archive/System Backups"
sudo mkdir -p "/Volumes/Archive/Documents"

# Set permissions
sudo chown -R $(whoami):staff "/Volumes/Archive"
sudo chmod -R 755 "/Volumes/Archive"
```

### Media Management Best Practices

#### File Naming Conventions

**Movies:**
- `Movie Title (Year).ext`
- Example: `The Matrix (1999).mkv`

**TV Shows:**
- `Show Name - S##E## - Episode Title.ext`
- Example: `Breaking Bad - S01E01 - Pilot.mkv`

**Music:**
- `## - Track Name.ext`
- Example: `01 - Bohemian Rhapsody.mp3`

#### Adding New Content

```bash
# 1. Upload to staging area
cp new_movie.mkv "/Volumes/warmstore/New Uploads/"

# 2. Rename properly
mv "/Volumes/warmstore/New Uploads/new_movie.mkv" \
   "/Volumes/warmstore/Movies/Movie Title (2023)/Movie Title (2023).mkv"

# 3. Fix permissions
chmod 644 "/Volumes/warmstore/Movies/Movie Title (2023)/Movie Title (2023).mkv"

# 4. Trigger Plex scan
# Plex will auto-scan, or force scan in Plex settings
```

#### Bulk Organization Scripts

**Movie Organization Script:**
```bash
#!/bin/bash
# organize_movies.sh
MOVIES_DIR="/Volumes/warmstore/Movies"
STAGING_DIR="/Volumes/warmstore/New Uploads"

for file in "$STAGING_DIR"/*.{mkv,mp4,avi}; do
    if [[ -f "$file" ]]; then
        basename=$(basename "$file" .${file##*.})
        # Extract year if present
        if [[ $basename =~ \(([0-9]{4})\) ]]; then
            year=${BASH_REMATCH[1]}
            title=$(echo "$basename" | sed "s/ *($year) *//")
            mkdir -p "$MOVIES_DIR/$title ($year)"
            mv "$file" "$MOVIES_DIR/$title ($year)/$title ($year).${file##*.}"
            echo "Organized: $title ($year)"
        fi
    fi
done
```

**TV Show Organization Script:**
```bash
#!/bin/bash
# organize_tv.sh
TV_DIR="/Volumes/warmstore/TV Shows"
STAGING_DIR="/Volumes/warmstore/New Uploads"

for file in "$STAGING_DIR"/*.{mkv,mp4,avi}; do
    if [[ -f "$file" ]]; then
        basename=$(basename "$file")
        # Extract show name, season, episode
        if [[ $basename =~ (.+)[._-][Ss]([0-9]+)[Ee]([0-9]+) ]]; then
            show="${BASH_REMATCH[1]//./ }"
            season="${BASH_REMATCH[2]}"
            episode="${BASH_REMATCH[3]}"
            
            # Clean show name
            show=$(echo "$show" | sed 's/[._-]/ /g' | xargs)
            
            # Create directory structure
            mkdir -p "$TV_DIR/$show/Season $(printf "%02d" $season)"
            
            # Move and rename file
            mv "$file" "$TV_DIR/$show/Season $(printf "%02d" $season)/"
            echo "Organized: $show S${season}E${episode}"
        fi
    fi
done
```

### Storage Monitoring & Maintenance

#### Check Storage Usage

```bash
# Overall storage usage
df -h /Volumes/*

# Detailed usage by directory
du -sh /Volumes/warmstore/* | sort -hr
du -sh /Volumes/faststore/* | sort -hr
du -sh /Volumes/Archive/* | sort -hr

# Find large files
find /Volumes/warmstore -size +5G -type f -exec ls -lh {} \;
```

#### Clean Up and Optimization

```bash
# Find duplicate files (install fdupes first: brew install fdupes)
fdupes -r /Volumes/warmstore/Movies/

# Find empty directories
find /Volumes/warmstore -type d -empty

# Check for permission issues
find /Volumes/warmstore -type f ! -perm 644
find /Volumes/warmstore -type d ! -perm 755

# Fix common permission issues
sudo chown -R $(whoami):staff /Volumes/warmstore
sudo find /Volumes/warmstore -type f -exec chmod 644 {} \;
sudo find /Volumes/warmstore -type d -exec chmod 755 {} \;
```

### Automated Organization

#### Create LaunchAgent for Auto-Organization

```bash
# Create organization script
cat > ~/bin/auto_organize_media.sh << 'EOF'
#!/bin/bash
STAGING="/Volumes/warmstore/New Uploads"
PROCESSED="/Volumes/warmstore/To Process"

# Only run if staging directory has content
if [[ $(ls -A "$STAGING" 2>/dev/null) ]]; then
    echo "$(date): Starting media organization..."
    
    # Run organization scripts
    ~/bin/organize_movies.sh
    ~/bin/organize_tv.sh
    
    # Move any remaining files to processing
    mv "$STAGING"/* "$PROCESSED"/ 2>/dev/null || true
    
    echo "$(date): Media organization complete"
fi
EOF

chmod +x ~/bin/auto_organize_media.sh

# Create LaunchAgent (optional)
# This would run every hour to organize new uploads
```

#### Integration with Download Tools

If using download automation tools:

```bash
# Configure download tools to use staging directory
DOWNLOAD_DIR="/Volumes/warmstore/New Uploads"

# Tools like Sonarr/Radarr can be configured to:
# 1. Download to staging area
# 2. Trigger organization scripts
# 3. Update Plex library automatically
```

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
df -h /Volumes/faststore

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
du -sh /Volumes/warmstore/* | sort -hr
du -sh /Volumes/faststore/* | sort -hr
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
# Backup media storage (manual rsync)
rsync -av --progress /Volumes/warmstore/ /Volumes/Backup/MediaBackup/

# Backup photo storage (manual rsync)
rsync -av --progress /Volumes/faststore/ /Volumes/Backup/PhotoBackup/

# Backup Immich database
cd services/immich
docker-compose exec database pg_dump -U postgres immich > /Volumes/Backup/immich_db_$(date +%Y%m%d).sql

# Create backup script for convenience
cat > ~/bin/backup_media.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/Volumes/Backup"
DATE=$(date +%Y%m%d)

echo "Starting backup at $(date)"
rsync -av --progress /Volumes/warmstore/ "$BACKUP_DIR/MediaBackup_$DATE/"
rsync -av --progress /Volumes/faststore/ "$BACKUP_DIR/PhotoBackup_$DATE/"
echo "Backup completed at $(date)"
EOF

chmod +x ~/bin/backup_media.sh
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
find /Volumes/warmstore -name "*.tmp" -delete
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
