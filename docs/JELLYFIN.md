# 🎬 Jellyfin Setup & Usage Guide

Complete guide for setting up and using Jellyfin Media Server on your Mac mini home server as an alternative to Plex for remote video streaming.

## 📋 Overview

Jellyfin is a free, open-source media server that runs **natively** on macOS for optimal performance and hardware transcoding support. Unlike Plex, Jellyfin has no subscription fees, no relay service limitations, and works seamlessly with Tailscale for remote access.

**Key Advantages**:
- ✅ **Completely free** - No premium features or subscriptions
- ✅ **No relay service** - Direct connections only
- ✅ **Perfect for Tailscale** - No authentication issues
- ✅ **Hardware transcoding** - VideoToolbox support on macOS
- ✅ **Open source** - Community-driven development

---

## 🚀 Installation

### Automated Installation
```bash
./scripts/services/install_jellyfin.sh
```

### What Gets Installed
- **Jellyfin Media Server**: Native macOS application  
- **FFmpeg**: Built-in transcoding engine
- **Web Interface**: HTML5 web client
- **Hardware Acceleration**: VideoToolbox support

### Manual Installation
1. Download from [jellyfin.org/downloads](https://jellyfin.org/downloads/)
2. Choose the correct version for your Mac:
   - **Apple Silicon (M1/M2/M3)**: ARM64 version
   - **Intel Mac**: x86_64 version
3. Install the `.dmg` file
4. Configure with setup scripts

---

## ⚙️ Initial Configuration

### 1. Configure Storage Paths
```bash
./scripts/services/configure_jellyfin.sh
```

This script:
- Moves Jellyfin data to faststore for performance
- Creates symlinks for seamless operation
- Backs up existing configuration
- Sets up transcoding directories

### 2. Start Jellyfin
```bash
./scripts/services/start_jellyfin_safe.sh
```

This script:
- Starts Jellyfin Media Server
- Waits for server to be ready
- Configures Tailscale serve for remote access
- Enables HTTPS on port 8096

### 3. First Launch
Open http://localhost:8096

### 4. Setup Wizard

**Step 1: Language & Display**
- Choose your preferred language
- Configure display name

**Step 2: Create Admin Account**
- **Username**: Your admin username
- **Password**: Secure password
- Email address (optional)

**Step 3: Media Libraries**

**Recommended folder structure**:
```
/Volumes/warmstore/
├── movies/
│   ├── Avatar (2009)/
│   │   └── Avatar (2009).mkv
│   └── Inception (2010)/
│       └── Inception (2010).mkv
└── tv-shows/
    ├── Breaking Bad/
    │   ├── Season 01/
    │   └── Season 02/
    └── The Office/
        ├── Season 01/
        └── Season 02/
```

**Add libraries**:
1. Click "Add Media Library"
2. **Movies**: `/Volumes/warmstore/movies`
3. **TV Shows**: `/Volumes/warmstore/tv-shows`
4. Configure metadata providers (TMDB recommended)

**Step 4: Preferred Metadata Language**
- Select your language
- Enable automatic metadata downloads

**Step 5: Remote Access**
- Enable remote connections: ✅
- Configure allowed networks (Tailscale will be added separately)

---

## 🔧 Storage Configuration

### Faststore Usage (SSD Performance)

**Configuration Paths**:
- **Config/Metadata**: `/Volumes/faststore/jellyfin/config`
- **Cache**: `/Volumes/faststore/jellyfin/cache`
- **Transcoding**: `/Volumes/faststore/jellyfin/transcoding`
- **Logs**: `/Volumes/faststore/jellyfin/logs`

**Symlink**:
- `~/Library/Application Support/jellyfin` → `/Volumes/faststore/jellyfin/config`

### Warmstore Usage (Media Storage)

**Media Libraries**:
- **Movies**: `/Volumes/warmstore/movies`
- **TV Shows**: `/Volumes/warmstore/tv-shows`
- **Music**: `/Volumes/warmstore/music` (optional)

### Verify Storage Setup
```bash
# Check symlink
ls -la ~/Library/Application\ Support/jellyfin

# Check faststore usage
du -sh /Volumes/faststore/jellyfin/*

# Check warmstore media
ls -la /Volumes/warmstore/
```

---

## 🎥 Transcoding Configuration

### Enable Hardware Acceleration

**Dashboard → Playback → Transcoding**:

1. **Transcoding Temp Path**: `/Volumes/faststore/jellyfin/transcoding`
2. **Hardware Acceleration**: VideoToolbox
3. **Enable hardware decoding for**:
   - ✅ H264
   - ✅ H265/HEVC
   - ✅ MPEG2
   - ✅ VC1
   - ✅ VP9

4. **Enable hardware encoding for**:
   - ✅ H264
   - ✅ H265/HEVC

5. **Transcoding Thread Count**: Auto (recommended)

### Transcoding Performance

**Expected Performance** (Apple Silicon M1/M2):
- **1080p → 720p**: Real-time with hardware acceleration
- **4K → 1080p**: Real-time to 2x speed
- **Multiple streams**: 2-3 simultaneous transcodes

**Check Transcoding Activity**:
```bash
# View transcoding logs
tail -f /Volumes/faststore/jellyfin/logs/*.log | grep Transcode

# Check CPU usage
top -l 1 | grep -A 10 "CPU usage"
```

---

## 🌐 Remote Access (Tailscale)

### Automatic Configuration

When you run `start_jellyfin_safe.sh`, Tailscale serve is automatically configured:

**Remote URL**: `https://nitins-mac-mini.tailb6b278.ts.net:8096`

### Manual Configuration

If needed, configure Tailscale serve manually:
```bash
tailscale serve --bg --https=8096 http://localhost:8096
```

### Verify Remote Access
```bash
# Check Tailscale serve status
tailscale serve status

# Test from another device
curl -k https://nitins-mac-mini.tailb6b278.ts.net:8096
```

---

## 📱 Mobile App Setup

### Download Apps
- **iOS**: [Jellyfin on App Store](https://apps.apple.com/app/jellyfin-mobile/id1480192618)
- **Android**: [Jellyfin on Google Play](https://play.google.com/store/apps/details?id=org.jellyfin.mobile)

### Configuration

**Local Network**:
- **Server Address**: `http://192.168.x.x:8096` (your Mac IP)
- **Login**: Same username/password from setup

**Remote Access (Tailscale)**:
- **Server Address**: `https://nitins-mac-mini.tailb6b278.ts.net:8096`
- **Login**: Same username/password from setup
- **No Plex Pass required!** ✅

### Download Settings

1. **Enable Downloads**: ✅
2. **Download Quality**: Choose based on device storage
3. **Download Location**: App storage

---

## ⚙️ Optimization Settings

### Network Settings

**Dashboard → Network**:
- **LAN Networks**: `192.168.0.0/16,172.16.0.0/12,10.0.0.0/8,100.0.0.0/8`
- **Enable automatic port mapping**: ❌ (using Tailscale)
- **External domain**: Leave empty (using Tailscale)

### Playback Settings

**Dashboard → Playback**:
- **Allow video playback that requires conversion**: ✅
- **Allow audio playback that requires conversion**: ✅
- **Internet streaming quality**: Auto (recommended)
- **Video bit depth**: Auto

### Library Settings

**Dashboard → Libraries**:
- **Scan library on startup**: ❌ (manual scan recommended)
- **Real-time monitoring**: ✅ (if performance allows)
- **Extract chapter images**: ✅ (for scrubbing)
- **Enable Trickplay image extraction**: ✅ (for preview thumbnails)

---

## 🔍 Monitoring & Maintenance

### Check Server Status
```bash
# Check if Jellyfin is running
pgrep -f "Jellyfin Server"

# Check web interface
curl -s http://localhost:8096/health

# Check via Tailscale
curl -k https://nitins-mac-mini.tailb6b278.ts.net:8096
```

### View Logs
```bash
# Main server log
tail -f /Volumes/faststore/jellyfin/logs/*.log

# Transcoding activity
tail -f /Volumes/faststore/jellyfin/logs/*.log | grep Transcode

# Errors only
tail -f /Volumes/faststore/jellyfin/logs/*.log | grep -i error
```

### Monitor Storage Usage
```bash
# Faststore usage (config/cache/transcoding)
du -sh /Volumes/faststore/jellyfin/*

# Warmstore usage (media)
du -sh /Volumes/warmstore/movies /Volumes/warmstore/tv-shows
```

### Performance Monitoring

**Dashboard → Server → Logs**:
- View real-time activity
- Monitor playback sessions
- Check transcoding performance

---

## 🔄 Comparison with Plex

| Feature | Jellyfin | Plex |
|---------|----------|------|
| **Cost** | ✅ Free | ❌ Limited (Plex Pass required) |
| **Hardware Transcoding** | ✅ Free | ❌ Requires Plex Pass |
| **Remote Access** | ✅ Direct | ❌ Relay service issues |
| **Tailscale Integration** | ✅ Perfect | ❌ Authentication issues |
| **Open Source** | ✅ Yes | ❌ No |
| **Subscriptions** | ✅ None | ❌ $5-$40/month |
| **Mobile Apps** | ✅ Free | ❌ Limited without Pass |
| **User Interface** | ✅ Modern | ✅ Polished |

---

## 🚨 Troubleshooting

### Jellyfin Won't Start
```bash
# Check if already running
pgrep -f "Jellyfin Server"

# Kill existing process
killall "Jellyfin Server"

# Restart
./scripts/services/start_jellyfin_safe.sh
```

### Remote Access Not Working
```bash
# Check Tailscale serve
tailscale serve status

# Re-enable Tailscale serve
tailscale serve --bg --https=8096 http://localhost:8096

# Verify from another device
curl -k https://nitins-mac-mini.tailb6b278.ts.net:8096
```

### Transcoding Fails
```bash
# Check transcoding directory permissions
ls -la /Volumes/faststore/jellyfin/transcoding

# Check hardware acceleration
# Dashboard → Playback → Transcoding → Test

# View transcoding logs
tail -f /Volumes/faststore/jellyfin/logs/*.log | grep Transcode
```

### Metadata Not Downloading
```bash
# Check internet connection
ping tmdb.org

# Dashboard → Server → Scheduled Tasks
# Run "Scan All Libraries"
# Run "Refresh all metadata"
```

---

## 🔗 Useful Links

- **Official Documentation**: https://jellyfin.org/docs/
- **Community Forum**: https://forum.jellyfin.org/
- **GitHub**: https://github.com/jellyfin/jellyfin
- **Mobile Apps**: https://jellyfin.org/downloads/clients
- **Feature Requests**: https://features.jellyfin.org/

---

## 📚 Related Documentation

- **[Plex Setup](PLEX.md)** - Alternative media server
- **[Immich Setup](IMMICH.md)** - Photo management
- **[Tailscale Setup](TAILSCALE.md)** - Remote access
- **[Storage Management](STORAGE.md)** - RAID and storage
- **[Diagnostics](DIAGNOSTICS.md)** - Troubleshooting tools

---

**Need help?** Check the [Troubleshooting Guide](TROUBLESHOOTING.md) or run diagnostics with `./diagnostics/run_all.sh`.

