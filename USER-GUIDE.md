# 🏠 Home Media Server - User Guide

**Your Personal Netflix + Google Photos**  
Stream movies, manage photos, accessible anywhere on any device.

---

## 🚀 What You Have

After setup, you have a complete home media server with:

- **🎬 Plex Media Server** - Stream movies, TV shows, music (like Netflix)
- **📸 Immich** - Self-hosted photo backup and browsing (like Google Photos)
- **🔒 Secure Remote Access** - Access from anywhere via Tailscale VPN

**🌐 Your Server URLs:**
- **Main Dashboard:** `https://your-device.your-tailnet.ts.net`
- **Photos (Immich):** `https://your-device.your-tailnet.ts.net:2283`
- **Media (Plex):** `https://your-device.your-tailnet.ts.net:32400`

### 🔍 Finding Your Server URL

**Ask your server administrator for the URLs:**
- They can find the exact hostname using admin commands
- The format will be something like: `device-name.tailnet-id.ts.net`

**Example URLs you'll receive:**
- Dashboard: `https://homeserver.tail9x8y7z.ts.net`
- Photos: `https://homeserver.tail9x8y7z.ts.net:2283`
- Media: `https://homeserver.tail9x8y7z.ts.net:32400`

> **For Administrators:** See [ADMIN-GUIDE.md](ADMIN-GUIDE.md) for commands to get server hostnames and manage users.

---

## 📱 Mobile Setup Guide

> **⚠️ IMPORTANT:** Before you start, you need to be invited to the Tailscale network by the home server administrator. You cannot access the server without this invitation.

### Getting Network Access

#### 1. Request Access from Admin
**What to ask your admin:**
- "Please invite me to the Tailscale network"
- "I need access to the home media server"
- They will need your email address

**What the admin needs to do:**
1. Log into [Tailscale Admin Console](https://login.tailscale.com/admin/)
2. Go to "Users" → "Invite users"
3. Enter your email address
4. Send invitation

**You will receive:**
- Email invitation to join the Tailscale network
- Instructions to create your account (if you don't have one)

### iPhone & iPad Setup

#### 1. Install Tailscale
1. Download **Tailscale** from the App Store
2. **Accept the invitation** from the email you received
3. Sign in with your Tailscale account (create one if needed)
4. Connect to your network
5. ✅ You can now access your server securely

#### 2. Plex App (Movies & TV)
1. Download **Plex** from the App Store
2. Sign in to your Plex account
3. **Add Server Manually:**
   - Server Name: `Home Server`
   - Server Address: `your-device.your-tailnet.ts.net:32400`
   - OR: `https://your-device.your-tailnet.ts.net:32400`
4. ✅ Start streaming your media library

#### 3. Immich App (Photos)
1. Download **Immich** from the App Store
2. **Server Settings:**
   - Server URL: `https://your-device.your-tailnet.ts.net:2283`
   - Username/Password: *(created during setup)*
3. **Enable Auto-Backup:**
   - Go to Settings → Auto Backup
   - Choose photo quality and frequency
4. ✅ Your photos will backup automatically

### Android Setup

#### 1. Install Tailscale
1. Download **Tailscale** from Google Play Store
2. **Accept the invitation** from the email you received
3. Sign in with your Tailscale account (create one if needed)
4. Connect to your network
5. ✅ Secure access enabled

#### 2. Plex App (Movies & TV)
1. Download **Plex** from Google Play Store
2. Sign in to your Plex account
3. **Manual Server Connection:**
   - Tap "Got It" when it says no servers found
   - Tap "+" to add server manually
   - Connection: `your-device.your-tailnet.ts.net:32400`
4. ✅ Stream your content anywhere

#### 3. Immich App (Photos)
1. Download **Immich** from Google Play Store
2. **Initial Setup:**
   - Server Endpoint URL: `https://your-device.your-tailnet.ts.net:2283`
   - Login with your credentials
3. **Auto-Upload Setup:**
   - Settings → Auto Upload
   - Select albums to backup
   - Choose upload quality
4. ✅ Automatic photo backup activated

---

## 💻 Web Browser Access

### Any Device with Web Browser

#### Access Methods:
1. **Dashboard:** `https://your-device.your-tailnet.ts.net`
   - Central hub with links to all services
   - Service status indicators
   - One-click access to photos and media

2. **Direct Photo Access:** `https://your-device.your-tailnet.ts.net:2283`
   - Full Immich web interface
   - Upload, organize, and share photos
   - Create albums and search by content

3. **Direct Media Access:** `https://your-device.your-tailnet.ts.net:32400`
   - Full Plex web interface
   - Stream to any device
   - Manage libraries and users

#### First-Time Setup:
1. **Get Invited to Tailscale Network:**
   - Ask admin to invite you (they need your email)
   - Accept email invitation
   - Install Tailscale on your device
   - Sign in and connect
2. **Open Browser** and navigate to your dashboard URL
3. **Bookmark** your favorite services

---

## 🎬 Using Plex (Your Personal Netflix)

### Adding Media Content

#### 1. Organize Your Media Files
```
/Volumes/Media/
├── Movies/
│   ├── The Matrix (1999)/
│   │   └── The Matrix (1999).mkv
│   └── Inception (2010)/
│       └── Inception (2010).mp4
├── TV Shows/
│   ├── Breaking Bad/
│   │   ├── Season 01/
│   │   └── Season 02/
│   └── The Office/
└── Music/
    └── Artist Name/
        └── Album Name/
```

#### 2. Plex Will Automatically:
- **Scan** for new content every few hours
- **Download** movie posters and descriptions
- **Match** TV show episodes with episode info
- **Create** a beautiful browsing interface

#### 3. Manual Library Update:
- **Web:** Settings → Libraries → Scan Library Files
- **App:** Pull down to refresh on library screens

### Streaming Features

#### Quality & Transcoding:
- **Original Quality:** Direct stream (fastest)
- **Automatic:** Plex adjusts based on connection
- **Mobile:** Lower quality saves cellular data
- **Home Network:** Always highest quality

#### Multiple Users:
- **Admin Account:** Full access and control
- **Friends/Family:** Create accounts in Plex Settings
- **Restricted Access:** Control what content each user sees

---

## 📸 Using Immich (Your Personal Google Photos)

### Photo Management

#### 1. Automatic Backup
- **Mobile Apps:** Auto-upload photos and videos
- **Quality Options:** Original, High, Medium
- **Background Sync:** Works even when app is closed
- **Cellular Control:** Choose WiFi-only or allow cellular

#### 2. Web Upload
- **Drag & Drop:** Multiple photos at once
- **Browser Upload:** Click "+" button to select files
- **Bulk Import:** For large photo collections

#### 3. Organization Features
- **Automatic Albums:** By date, location, people
- **Manual Albums:** Create custom collections
- **Search:** By content, location, date, people
- **Tags:** Add custom labels to photos

### Advanced Features

#### 1. Face Recognition
- **People Tab:** Automatically groups photos by faces
- **Name People:** Add names to organize by person
- **Search:** "Show me photos of John"

#### 2. Location & Maps
- **GPS Data:** Photos with location show on map
- **Location Search:** "Photos taken in Paris"
- **Timeline:** See photos by location over time

#### 3. Sharing & Export
- **Share Albums:** Generate links for family/friends
- **Download:** Original quality downloads
- **External Sharing:** Copy links for social media

### Google Photos Migration

#### 1. Export from Google
- **Google Takeout:** Request data export
- **Download:** Large ZIP files with all photos
- **Extract:** Unzip to organized folders

#### 2. Import to Immich
- **Web Upload:** Drag folders to Immich web interface
- **Mobile Upload:** Use phone app for recent photos
- **Metadata:** Preserves creation dates and location data

---

## 🔧 Troubleshooting

### Connection Issues

#### Can't Access Server?
1. **Check Tailscale:**
   - Is Tailscale app connected?
   - Try disconnecting and reconnecting
2. **Get Correct Hostname:**
   - Ask server admin for exact URL
   - Verify format: `device-name.tailnet-id.ts.net`
3. **Check URL:**
   - Try both HTTP and HTTPS
   - Ensure you're using the full hostname with port numbers
4. **Restart Tailscale:**
   - Close and reopen Tailscale app
   - On server: `sudo tailscale down && sudo tailscale up`

#### Slow Streaming?
1. **Local Network:** Use local IP when at home
2. **Quality Settings:** Lower quality for remote access
3. **Internet Speed:** Check upload speed at home
4. **App Settings:** Enable "Use cellular data" if needed

### Plex Issues

#### No Movies Showing?
1. **Library Scan:** Force manual scan in settings
2. **File Names:** Check movie file naming
3. **Permissions:** Ensure Plex can read media folders
4. **Restart:** Restart Plex Media Server if needed

#### Playback Problems?
1. **Direct Play:** Check if your device supports the file format
2. **Transcoding:** Server may need to convert files (slower)
3. **Network:** Check connection speed during playback
4. **Quality:** Lower quality setting for better playback

### Immich Issues

#### Photos Not Uploading?
1. **Storage Space:** Check available storage on server
2. **App Permissions:** Allow camera and storage access
3. **Network:** Ensure good WiFi/cellular connection
4. **App Update:** Update to latest Immich app version

#### Missing Photos?
1. **Upload Status:** Check upload queue in app
2. **Date Range:** Use date filters to find specific photos
3. **Albums:** Check if photos are in albums
4. **Search:** Try searching by content or date

---

## 📲 Quick Setup Checklist

### For New Users:

#### On Your Phone:
- [ ] Install Tailscale app
- [ ] Connect to your Tailscale network
- [ ] Install Plex app
- [ ] Add your server to Plex
- [ ] Install Immich app
- [ ] Configure photo backup
- [ ] Test accessing both services

#### On Your Computer:
- [ ] Install Tailscale
- [ ] Connect to network
- [ ] Bookmark your dashboard URL
- [ ] Test web access to both services
- [ ] Set up media organization folders

#### First Content:
- [ ] Add some movies to `/Volumes/Media/Movies/`
- [ ] Upload test photos to Immich
- [ ] Verify everything works on mobile
- [ ] Share access with family members

---

## 🎯 Pro Tips

### Optimize Your Experience:

#### Plex Optimization:
- **Name files properly** for automatic metadata
- **Use SSD storage** for frequently watched content
- **Enable remote access** in Plex settings
- **Create user accounts** for family members

#### Immich Optimization:
- **Enable face detection** for better search
- **Create albums** for special events
- **Use auto-backup** to never lose photos
- **Set up regular exports** as additional backup

#### General Tips:
- **Bookmark** your dashboard for quick access
- **Use WiFi** whenever possible to save cellular data
- **Update apps** regularly for new features
- **Restart services** monthly for optimal performance

---

## 🆘 Need Help?

### Common User Commands:

```bash
# Check your Tailscale connection status
tailscale status

# Test server connectivity (replace with your actual hostname)
curl -I https://your-device.your-tailnet.ts.net:2283
```

### For Administrators:

See [ADMIN-GUIDE.md](ADMIN-GUIDE.md) for server management commands including:
- Getting server hostnames
- Managing users
- System diagnostics and maintenance
- Service restart commands

### Support Resources:
- **Plex Support:** https://support.plex.tv/
- **Immich Documentation:** https://immich.app/docs/
- **Tailscale Help:** https://tailscale.com/kb/

---

**🎉 Enjoy your personal media server!**  
*Stream anywhere, backup everything, own your data.*
