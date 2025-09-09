# 🎬 Plex Setup & Usage Guide

Comprehensive guide for setting up and using Plex Media Server on your Mac mini home server.

## 📋 Overview

Plex Media Server runs **natively** on macOS (not in Docker) for optimal performance and hardware transcoding support. This guide covers installation, configuration, optimization, and remote access.

---

## 🚀 Installation

### Automated Installation
```bash
./scripts/31_install_native_plex.sh
```

### What Gets Installed
- **Plex Media Server**: Native macOS application  
- **LaunchAgent**: Auto-start on boot
- **System Integration**: Hardware transcoding access

### Manual Installation
1. Download from [plex.tv/downloads](https://www.plex.tv/downloads/)
2. Install the `.pkg` file
3. Configure auto-start (handled by setup scripts)

---

## ⚙️ Initial Configuration

### 1. First Launch
Open http://localhost:32400/web

### 2. Account Setup
- Sign in with your Plex account (create one if needed)
- Name your server (e.g., "Mac Mini HomeServer")
- Choose privacy settings

### 3. Library Setup

**Recommended folder structure**:
```
/Volumes/Media/
├── Movies/
│   ├── Avatar (2009)/
│   │   └── Avatar (2009).mkv
│   └── Inception (2010)/
│       └── Inception (2010).mkv
├── TV/
│   ├── Breaking Bad/
│   │   ├── Season 01/
│   │   └── Season 02/
│   └── The Office/
│       ├── Season 01/
│       └── Season 02/
└── Music/
    ├── Artist Name/
    │   └── Album Name/
    └── Various Artists/
```

**Add libraries**:
1. Settings → Libraries → Add Library
2. **Movies**: `/Volumes/Media/Movies`
3. **TV Shows**: `/Volumes/Media/TV`  
4. **Music**: `/Volumes/Media/Music`

---

## 🔧 Optimization Settings

### Hardware Transcoding (Recommended)

**Requirements**: 
- Apple Silicon Mac (M1, M2, etc.) or Intel Mac with QuickSync

**Enable**:
1. Settings → Transcoder  
2. ✅ **Use hardware acceleration when available**
3. **Hardware transcoding device**: Auto or Apple VideoToolbox

### Quality Settings

**Remote Quality**:
- Settings → Network → Remote Access
- **Internet upload speed**: Test and set accurately
- **Limit remote stream bitrate**: Based on your upload speed

**Local Quality**:
- Settings → Network → LAN Networks
- Add your local network (e.g., `192.168.1.0/24`)
- **Treat WAN IP As LAN**: ✅ (for Tailscale)

### Performance Tuning

**Transcoding**:
```bash
# Check transcoding activity
tail -f "/Users/$(whoami)/Library/Logs/Plex Media Server/Plex Media Server.log" | grep Transcode
```

**Storage Optimization**:
- **Metadata**: Stored in `~/Library/Application Support/Plex Media Server`
- **Transcoding temp**: Configure in Settings → Transcoder → Advanced
- **Consider**: Move temp to faster storage if needed

---

## 🌐 Remote Access

### Local Network Access
- **URL**: http://your-local-ip:32400/web
- **Auto-discovery**: Most Plex apps find the server automatically

### Tailscale Access (Recommended)

**Setup HTTPS serving**:
```bash
sudo tailscale serve --https=32400 http://localhost:32400
```

**Access URLs**:
- **Web**: `https://your-macmini.your-tailnet.ts.net:32400`
- **Mobile apps**: Use server IP `your-macmini.your-tailnet.ts.net:32400`

### Reverse Proxy Access

**With Caddy reverse proxy enabled**:
- **Web**: `https://your-macmini.your-tailnet.ts.net/plex`
- **Direct link**: `https://your-macmini.your-tailnet.ts.net/plex/web`

### Plex Relay (Fallback)

If direct access fails, Plex uses relay servers:
- Settings → Network → Show Advanced
- ✅ **Enable Relay**: For fallback access
- **Manual port**: 32400 (if opening firewall)

---

## 📱 Mobile & Client Setup

### Plex Mobile Apps

**Server Configuration**:
1. Download Plex app (iOS/Android)
2. Sign in with your account
3. **Manual server**: `your-macmini.your-tailnet.ts.net:32400`
4. **Or**: Let app auto-discover

**Optimization**:
- **Download quality**: Adjust for mobile data usage
- **Sync**: Download content for offline viewing
- **Remote quality**: Match your network speed

### Desktop Clients

**Plex Media Player**:
- Download from plex.tv
- Better performance than web player
- Hardware decoding support

**Web Player**:
- No installation required
- Good for occasional use
- Limited codec support

### TV Clients

**Apple TV**:
- Download Plex app from App Store
- Auto-discovers server on local network
- Excellent performance with hardware decoding

**Other Platforms**:
- Roku, Fire TV, Smart TVs
- Use manual server configuration with Tailscale IP

---

## 📁 Media Management

### File Organization

**Naming Conventions**:
```bash
# Movies
Movie Name (Year)/Movie Name (Year).ext

# TV Shows  
Show Name/Season ##/Show Name - S##E## - Episode Name.ext

# Music
Artist Name/Album Name/## - Track Name.ext
```

**Supported Formats**:
- **Video**: MP4, MKV, AVI, MOV, M4V
- **Audio**: MP3, FLAC, AAC, M4A, OGG
- **Subtitles**: SRT, ASS, SSA, PGS

### Automatic Organization

**File monitoring**:
- Plex automatically scans for changes
- **Scan interval**: Configurable in library settings
- **Real-time**: Enable for immediate updates

**Metadata Sources**:
- **Movies**: TheMovieDB (TMDb)
- **TV**: TheTVDB  
- **Music**: MusicBrainz, Last.fm

### Import Tools

**For large collections**:
```bash
# Use rsync for efficient copying
rsync -av --progress /source/Movies/ /Volumes/Media/Movies/

# Maintain permissions
chown -R $(whoami):staff /Volumes/Media/
chmod -R 755 /Volumes/Media/
```

---

## 🔍 Monitoring & Diagnostics

### Health Checks
```bash
# Check if Plex is running
./diagnostics/check_plex_native.sh

# Manual process check
ps aux | grep "Plex Media Server"
```

### Performance Monitoring

**Activity Dashboard**:
- Settings → Status → Dashboard
- Shows active streams and transcoding

**Logs**:
```bash
# View recent logs
tail -f ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log

# Error logs
grep ERROR ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log
```

### Storage Usage
```bash
# Check media storage
du -sh /Volumes/Media/*

# Check metadata storage  
du -sh ~/Library/Application\ Support/Plex\ Media\ Server/
```

---

## 🔧 Troubleshooting

### Common Issues

**Server not starting**:
```bash
# Check LaunchAgent status
launchctl list | grep plex

# Restart manually
launchctl unload ~/Library/LaunchAgents/com.plexapp.plexmediaserver.plist
launchctl load ~/Library/LaunchAgents/com.plexapp.plexmediaserver.plist
```

**Remote access issues**:
1. Check Tailscale connection: `tailscale status`
2. Verify HTTPS serving: `sudo tailscale serve status`
3. Test local access first: http://localhost:32400/web

**Transcoding problems**:
- **No hardware acceleration**: Check Mac model compatibility
- **Slow transcoding**: Monitor CPU usage and storage speed
- **Quality issues**: Adjust transcoding settings

**Library not updating**:
1. Settings → Library → Scan Library Files
2. Check folder permissions on `/Volumes/Media`
3. Verify file naming conventions

### Performance Issues

**High CPU usage**:
- Enable hardware transcoding
- Reduce concurrent streams
- Check for background maintenance tasks

**Storage issues**:
- Clean transcoding cache: Settings → Transcoder → Reset
- Move metadata to faster storage if needed
- Monitor available space

### Log Analysis
```bash
# Find transcoding errors
grep -i "transcode.*error" ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log

# Check database issues
grep -i "database" ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log

# Network connectivity
grep -i "network\|connection" ~/Library/Logs/Plex\ Media\ Server/Plex\ Media\ Server.log
```

---

## 📈 Advanced Configuration

### Custom Transcoding

**Transcoder settings**:
- **Use hardware acceleration**: ✅ Enabled
- **Background transcoding**: For mobile sync
- **Transcoder quality**: Balance quality vs. performance

### Multiple Libraries

**Separate user content**:
```bash
/Volumes/Media/
├── Kids/
│   ├── Movies/
│   └── TV/
├── Adult/
│   ├── Movies/
│   └── TV/
└── Shared/
    └── Music/
```

### Plex Pass Features

**Premium features** (subscription required):
- **Mobile sync**: Download for offline
- **Live TV & DVR**: With tuner hardware
- **Premium music features**: Lyrics, sonic analysis
- **Parental controls**: User restrictions

---

## 🔒 Security & Access Control

### User Management

**Local users**:
- Settings → Users & Sharing → Friends
- **Home users**: Family members with full access
- **Friends**: External users with limited access

**Content restrictions**:
- **Rating limits**: By age/content rating
- **Library access**: Restrict specific libraries
- **Parental controls**: Time limits, content filtering

### Network Security

**Tailscale integration**:
- All traffic encrypted via Tailscale mesh
- No direct internet exposure
- Access control via Tailscale admin

**Local network**:
- Restrict to specific IP ranges
- Disable public access
- Use HTTPS where possible

---

## 📊 Maintenance

### Regular Tasks

**Weekly**:
```bash
# Check server health
./diagnostics/check_plex_native.sh

# Monitor storage usage
df -h /Volumes/Media
```

**Monthly**:
```bash
# Clear transcoding cache if needed
# Settings → Transcoder → Reset Transcoder

# Update Plex server (check for updates in web UI)

# Review user activity logs
```

### Backup Procedures

**Media backup**:
```bash
# Backup to external drive
./scripts/14_backup_store.sh warmstore /Volumes/MyBackup/MediaBackup
```

**Metadata backup**:
```bash
# Backup Plex metadata
rsync -av ~/Library/Application\ Support/Plex\ Media\ Server/ \
    /Volumes/MyBackup/PlexMetadata/
```

### Updates

**Server updates**:
- Settings → General → Updates
- **Download updates automatically**: ✅ Recommended
- **Install updates automatically**: Your choice

**Security updates**:
- Keep macOS updated for security patches
- Monitor Plex security announcements

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](QUICKSTART.md)** - Initial setup
- **📖 [Detailed Setup Guide](SETUP.md)** - Complete installation walkthrough  
- **🔒 [Tailscale Setup](TAILSCALE.md)** - Remote access configuration
- **💾 [Storage Management](STORAGE.md)** - Media storage optimization
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or run `./diagnostics/check_plex_native.sh` for health checks.
