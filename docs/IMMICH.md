# 📸 Immich Setup & Usage Guide

Complete guide for setting up and using Immich, your self-hosted Google Photos alternative, with photo backup, facial recognition, and Google Takeout import.

## 📋 Overview

Immich is a self-hosted photo and video management solution that runs in Docker containers. It provides:
- **Photo backup** from mobile devices
- **Facial recognition** and object detection
- **Timeline view** with memories and albums
- **Google Takeout import** for migration from Google Photos
- **Multi-user support** for families
- **Advanced search** with AI-powered features

---

## 🚀 Installation

### Automated Installation
```bash
# Set database password first
cd services/immich
cp .env.example .env
${EDITOR:-nano} .env

# Deploy all services
./scripts/30_deploy_services.sh
```

### What Gets Deployed

| Service | Purpose | Container | Port |
|---------|---------|-----------|------|
| **Immich Server** | Main web application | `immich-server` | 2283 |
| **Machine Learning** | AI features (faces, objects) | `immich-ml` | - |
| **PostgreSQL** | Database with vector extensions | `immich-db` | - |
| **Redis** | Cache and job queue | `immich-redis` | - |

### Storage Configuration
- **Photos/Videos**: `/Volumes/Photos` (faststore NVMe array)
- **Database**: Docker volume `immich-db`
- **Machine Learning**: Models cached in container

---

## ⚙️ Initial Configuration

### 1. First Launch
Open http://localhost:2283

### 2. Admin Account Setup
1. **Email**: Your email address (admin account)
2. **Password**: Secure password
3. **First Name**: Your name
4. **Last Name**: Your surname

### 3. Server Information
- **Server Name**: "Mac Mini HomeServer" (or custom name)
- **Welcome Message**: Optional custom message

### 4. Storage Settings
**Defaults are optimal**:
- **Upload Location**: `/photos` (maps to `/Volumes/Photos`)
- **Thumbnail Quality**: High
- **Preview Quality**: Medium

---

## 📱 Mobile App Setup

### Download Apps
- **iOS**: [Immich on App Store](https://apps.apple.com/app/immich/id1613945652)
- **Android**: [Immich on Google Play](https://play.google.com/store/apps/details?id=app.alextran.immich)

### Configuration

**Local Network**:
- **Server URL**: `http://your-mac-ip:2283`
- **Find IP**: `ifconfig | grep "inet " | grep -v 127.0.0.1`

**Remote Access (Tailscale)**:
- **Server URL**: `https://your-macmini.your-tailnet.ts.net`
- **Login**: Same email/password from web setup

**Reverse Proxy** *(if enabled)*:
- **Server URL**: `https://your-macmini.your-tailnet.ts.net/photos`

### Backup Settings

**Recommended configuration**:
1. **Auto Backup**: ✅ Enable
2. **Background Backup**: ✅ Enable  
3. **Foreground Backup**: ✅ Enable
4. **When to Backup**: 
   - ✅ WiFi only (recommended)
   - ⚠️ Mobile data (optional, uses data allowance)
5. **What to Backup**:
   - ✅ Photos
   - ✅ Videos
   - ✅ Recently added items only

---

## 🔍 AI & Machine Learning Features

### Facial Recognition

**Enable**:
1. Administration → Machine Learning → Facial Recognition
2. ✅ **Enable**: Facial recognition
3. **Max Distance**: 0.6 (default, adjust for accuracy)
4. **Min Faces**: 3 (minimum faces to create person)

**Usage**:
- **People tab**: Browse detected faces
- **Cluster faces**: Merge similar faces
- **Name people**: Add names to face clusters
- **Hide faces**: Remove false positives

### Object & Scene Detection

**Enable**:
1. Administration → Machine Learning → Smart Search
2. ✅ **Enable**: Smart search
3. **Model**: CLIP ViT-B-32 (default)

**Usage**:
- **Search**: "cat", "sunset", "birthday party"
- **Natural language**: "people at the beach"
- **Advanced**: Combine terms "dog AND park"

### EXIF & Metadata

**Features**:
- **GPS data**: Automatic location tagging
- **Camera info**: Device, lens, settings
- **Date/time**: Automatic timeline organization
- **Custom metadata**: Add descriptions and tags

---

## 📥 Google Takeout Import

Migrate your Google Photos library to Immich with the automated import tool.

### Prerequisites

**API Key Setup**:
1. Open Immich web UI: http://localhost:2283
2. Account (profile icon) → API Keys  
3. **Create API Key**: Give it a name (e.g., "Takeout Import")
4. **Copy the key**: Save for environment setup

**Environment Setup**:
```bash
export IMMICH_SERVER=http://localhost:2283
export IMMICH_API_KEY=your_api_key_here
```

### Google Takeout Preparation

**Request Google Takeout**:
1. Go to [Google Takeout](https://takeout.google.com)
2. **Deselect all**, then select **Photos**
3. **Format**: .tgz or .zip
4. **Size**: 50GB (or smaller for multiple files)
5. **Create export** and wait for download links

### Import Process

**Basic import** (extract only):
```bash
./scripts/70_takeout_to_immich.sh ~/Downloads/takeout-photos.zip
```

**Full import** (extract + upload):
```bash
# With API key configured
export IMMICH_SERVER=http://localhost:2283
export IMMICH_API_KEY=your_api_key_here

./scripts/70_takeout_to_immich.sh ~/Downloads/takeout-photos.zip
```

### Import Process Details

**What happens**:
1. **Extract**: Takeout archive to `/tmp/takeout-staging/`
2. **Process**: Remove Google metadata files
3. **Organize**: Flatten directory structure
4. **Upload**: Send to Immich via API *(if configured)*
5. **Cleanup**: Remove temporary files

**Manual upload** (if API not configured):
```bash
# Files extracted to:
/tmp/takeout-staging/processed/

# Upload via web UI:
# 1. Open http://localhost:2283
# 2. Click Upload (+ icon)
# 3. Select folders or drag & drop
```

### Large Takeout Handling

**Multiple archives**:
```bash
# Process each archive separately
./scripts/70_takeout_to_immich.sh ~/Downloads/takeout-001.zip
./scripts/70_takeout_to_immich.sh ~/Downloads/takeout-002.zip
```

**Monitor progress**:
```bash
# Check upload jobs
# Immich web UI → Administration → Jobs

# Check storage usage
df -h /Volumes/Photos
```

---

## 👥 Multi-User Setup

### Create Additional Users

**Admin tasks**:
1. Administration → Users
2. **Create User**: 
   - Email address
   - Password (or let user set)
   - Name information
3. **Storage quota**: Set limit if needed
4. **Admin privileges**: Only for trusted users

### User Configuration

**Each user gets**:
- Separate photo library
- Individual backup settings
- Personal albums and sharing
- Face recognition training

**Shared features**:
- Server-wide machine learning models
- Shared albums (if enabled)
- Timeline memories

### Family Sharing

**Shared albums**:
1. Create album in web UI
2. **Share album**: Add family member emails
3. **Permissions**: View or edit access

**Partner sharing** (coming in future updates):
- Automatic photo sharing between partners
- Facial recognition across accounts

---

## 🎨 Albums & Organization

### Albums

**Create albums**:
1. **Select photos**: Multiple selection in timeline
2. **Add to album**: Plus icon → New album
3. **Album name**: Descriptive name
4. **Description**: Optional details

**Smart albums** (planned feature):
- Automatic organization by date, location, people
- Dynamic albums based on search criteria

### Memories

**Automatic memories**:
- **On this day**: Photos from previous years
- **Random memories**: AI-selected highlights
- **Person memories**: Photos of specific people

**Memory configuration**:
- Administration → System Settings → Memory
- **Enable memories**: ✅ On
- **Years ago**: 1, 2, 3+ years

### Search & Discovery

**Search types**:
- **Text search**: Descriptions, file names
- **Object search**: "dog", "car", "mountain"
- **Face search**: Click on person
- **Location search**: City, landmark names
- **Date search**: Specific dates or ranges

**Advanced search**:
- **Combine terms**: "beach AND sunset"
- **Exclude terms**: "party NOT work"
- **Date ranges**: "2023" or "january 2023"

---

## 🔧 Administration

### System Settings

**Key settings**:
1. Administration → System Settings
2. **Theme**: Light, dark, or system
3. **Timezone**: Server timezone setting
4. **Map**: Enable/disable map features
5. **Password login**: Allow/disable password auth

### Storage Management

**Monitor usage**:
- Administration → Storage
- **Library statistics**: Photo/video counts
- **Storage usage**: Disk space used
- **Duplicate detection**: Find similar files

**Cleanup tools**:
- **Remove offline files**: Clean broken references
- **Delete empty albums**: Housekeeping
- **Repair jobs**: Fix database inconsistencies

### User Quota Management

**Current Status (2024)**:
Immich does not currently support per-user storage quotas in the standard configuration. However, there are several approaches to manage storage usage.

**Option 1: Display Quota Setting (Recommended)**
This fixes the storage display bug and provides visual feedback:

1. **Go to Administration** → **User Management**
2. **Edit each user account**
3. **Set storage quota** (e.g., 500GB)
4. **Save changes**

**Benefits**:
- ✅ Fixes storage display bug (shows correct size)
- ✅ Provides visual feedback to users
- ✅ Easy to configure per user

**Limitations**:
- ⚠️ Not a hard enforcement limit
- ⚠️ Must be set manually for each user

**Option 2: System-Level Monitoring**
Monitor total storage usage and set up alerts:

```bash
# Check storage usage
df -h /Volumes/faststore

# Check Immich directory size
du -sh /Volumes/faststore/immich

# Use the storage monitoring script
./scripts/core/check_storage_usage.sh
```

**Recommended Quota Distribution**:
```
User 1: 500GB
User 2: 500GB  
User 3: 500GB
System/Admin: 400GB
Total: 1.9TB (faststore capacity)
```

**Storage Monitoring Script**:
A monitoring script is available at `scripts/core/check_storage_usage.sh` that:
- Checks faststore and warmstore usage
- Provides color-coded status (OK/Warning/Critical)
- Shows detailed storage breakdown
- Can be run manually or scheduled

**Future Considerations**:
- Per-user quotas may be added in future Immich versions
- Monitor Immich GitHub for quota-related features
- Consider upgrading when quota management is available

### Jobs & Maintenance

**Background jobs**:
- Administration → Jobs
- **Thumbnail generation**: Create previews
- **Metadata extraction**: EXIF processing  
- **Machine learning**: Face/object detection
- **Video transcoding**: Format conversion

**Manual job triggers**:
- **Scan library**: Find new files
- **Generate thumbnails**: Recreate previews
- **Face detection**: Re-run ML analysis

### Backup & Export

**Database backup**:
```bash
# Backup Immich database
cd services/immich
docker compose exec database pg_dump -U postgres immich > immich_backup.sql
```

**Photo export**:
- **Timeline export**: Select photos → Download
- **Album export**: Download entire albums
- **API export**: Use CLI tools for bulk export

---

## 🔍 Monitoring & Diagnostics

### Health Checks
```bash
# Check all Immich containers
./diagnostics/check_docker_services.sh

# Manual check
cd services/immich && docker compose ps
```

### Performance Monitoring

**Container resources**:
```bash
# Real-time stats
docker stats

# Container logs
cd services/immich
docker compose logs immich-server
docker compose logs immich-ml
```

**Storage monitoring**:
```bash
# Photo storage usage
df -h /Volumes/Photos

# Database size
cd services/immich
docker compose exec database psql -U postgres -c "SELECT pg_size_pretty(pg_database_size('immich'));"
```

### Log Analysis

**Server logs**:
```bash
cd services/immich
docker compose logs -f immich-server | grep ERROR
```

**Machine learning logs**:
```bash
docker compose logs -f immich-ml
```

**Database logs**:
```bash
docker compose logs -f database
```

---

## 🔧 Troubleshooting

### Common Issues

**Upload failures**:
1. Check storage space: `df -h /Volumes/Photos`
2. Verify network connectivity
3. Check mobile app server URL
4. Restart containers: `cd services/immich && docker compose restart`

**Machine learning not working**:
```bash
# Check ML container
cd services/immich
docker compose logs immich-ml

# Restart ML service
docker compose restart immich-ml
```

**Database connection errors**:
1. Check `IMMICH_DB_PASSWORD` in `.env`
2. Restart database: `docker compose restart database`
3. Check database logs: `docker compose logs database`

**Mobile app sync issues**:
1. Verify server URL in app settings
2. Check WiFi vs mobile data settings
3. Force close and reopen app
4. Check server accessibility from device

### Performance Issues

**Slow uploads**:
- Check network speed between device and server
- Verify storage write speed on `/Volumes/Photos`
- Monitor server CPU/memory usage

**Slow web interface**:
- Check thumbnail generation jobs
- Verify adequate CPU/memory for containers
- Consider storage performance optimization

**Face detection slow**:
- ML processing is CPU intensive
- Check container resource allocation
- Consider scheduling during off-hours

### Recovery Procedures

**Reset machine learning**:
```bash
cd services/immich
docker compose down
docker volume rm immich_model-cache
docker compose up -d
```

**Database recovery**:
```bash
# Restore from backup
cd services/immich
docker compose exec database psql -U postgres immich < immich_backup.sql
```

**Full reset** (⚠️ DESTRUCTIVE):
```bash
cd services/immich
docker compose down -v  # Removes all data!
docker compose up -d
```

---

## 📈 Advanced Configuration

### Custom Domain

**With reverse proxy**:
- Access via: `https://your-macmini.your-tailnet.ts.net/photos`
- Mobile apps work with subdirectory paths

**Advanced DNS** (Tailscale MagicDNS):
- Configure custom subdomain if needed
- Update mobile app server URLs

### API Integration

**CLI tools**:
- [immich-go](https://github.com/immich-app/immich-go): Bulk operations
- Custom scripts using REST API
- Backup automation tools

**Integration examples**:
```bash
# Bulk upload with immich-go
immich-go -server=$IMMICH_SERVER -api=$IMMICH_API_KEY upload /path/to/photos

# API status check
curl -H "x-api-key: $IMMICH_API_KEY" $IMMICH_SERVER/api/server-info
```

### Performance Tuning

**Container resources**:
```bash
# Edit docker-compose.yml to add resource limits
cd services/immich
${EDITOR:-nano} docker-compose.yml

# Example resource limits:
# immich-server:
#   deploy:
#     resources:
#       limits:
#         memory: 4G
#       reservations:
#         memory: 2G
```

**Storage optimization**:
- **NVMe storage**: Optimal for photo storage
- **Thumbnail cache**: Consider separate fast storage
- **Database**: Monitor size and performance

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](QUICKSTART.md)** - Initial setup and configuration
- **📖 [Detailed Setup Guide](SETUP.md)** - Complete installation walkthrough
- **🔒 [Tailscale Setup](TAILSCALE.md)** - Remote access configuration
- **💾 [Storage Management](STORAGE.md)** - Photo storage optimization
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or run `./diagnostics/check_docker_services.sh` for health checks.
