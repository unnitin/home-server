
# 🏠 Home Server Setup Guide

Welcome to your personal home server! This guide will help you set up access to **Immich** (photo management) and **Plex** (media streaming) on your devices.

## 🔐 **Step 1: Install Tailscale (Required)**

Tailscale provides secure access to your home server from anywhere.

### **On Your Computer:**
1. Go to [tailscale.com](https://tailscale.com)
2. Click "Download" and install Tailscale
3. Sign in with your Google/Apple account
4. You'll be automatically connected to the home network

### **On Your iPhone:**
1. Download "Tailscale" from the App Store
2. Open the app and sign in with the same account
3. Toggle the switch to connect
4. You'll see "Connected" status

### **Verify Connection:**
- You should see your devices listed in the Tailscale app
- Look for "nitins-mac-mini" (the home server)

---

## 📸 **Step 2: Set Up Immich (Photo Management)**

Immich lets you backup, organize, and share photos with your family.

### **Web Access:**
1. **Open your browser** and go to:
   ```
   https://nitins-mac-mini.tailb6b278.ts.net:2283
   ```
2. **Create your account:**
   - Click "Sign Up"
   - Enter your email and create a password
   - Complete the setup wizard

### **iPhone App Setup:**
1. **Download "Immich"** from the App Store
2. **Open the app** and tap "Add Server"
3. **Enter server URL:**
   ```
   https://nitins-mac-mini.tailb6b278.ts.net:2283
   ```
4. **Sign in** with your account credentials
5. **Enable auto-backup:**
   - Go to Settings → Auto Backup
   - Toggle "Enable Auto Backup"
   - Choose which albums to backup
   - Set upload quality (Original recommended)

### **Key Features:**
- ✅ **Automatic photo backup** from your phone
- ✅ **Face recognition** and smart albums
- ✅ **Shared albums** with family members
- ✅ **Search by location, date, or people**
- ✅ **Original quality storage** (no compression)

---

## 🎬 **Step 3: Set Up Plex (Media Streaming)**

Plex streams your movies, TV shows, and music to all your devices.

### **Web Access:**
1. **Open your browser** and go to:
   ```
   https://nitins-mac-mini.tailb6b278.ts.net:32400
   ```
2. **Create your Plex account:**
   - Click "Sign Up" or "Sign In"
   - Link your account to the server
   - Complete the setup wizard

### **iPhone App Setup:**
1. **Download "Plex"** from the App Store
2. **Open the app** and sign in with your Plex account
3. **The server should appear automatically** (nitins-mac-mini)
4. **Tap to connect** and start browsing your media

### **Key Features:**
- ✅ **Stream movies and TV shows** in high quality
- ✅ **Download for offline viewing**
- ✅ **Continue watching** across devices
- ✅ **Family sharing** with separate profiles
- ✅ **Music streaming** with lyrics and artwork

---

## 🔧 **Step 4: Configure Your Accounts**

### **Immich Settings:**
1. **Go to Settings** (gear icon) → **User Management**
2. **Edit your user account**
3. **Set storage quota** to 500GB (fixes display bug)
4. **Enable sharing** if you want to share albums

### **Plex Settings:**
1. **Go to Settings** → **Users & Sharing**
2. **Create family profiles** if needed
3. **Set up parental controls** for kids
4. **Configure download quality** for mobile

---

## 📱 **Quick Access URLs**

Bookmark these URLs for easy access:

### **Immich (Photos):**
```
https://nitins-mac-mini.tailb6b278.ts.net:2283
```

### **Plex (Media):**
```
https://nitins-mac-mini.tailb6b278.ts.net:32400
```

### **Home Server Status:**
```
https://nitins-mac-mini.tailb6b278.ts.net
```

---

## 🆘 **Troubleshooting**

### **Can't Connect to Services:**
1. **Check Tailscale:** Make sure you're connected (green status)
2. **Try local URLs:** If Tailscale fails, try:
   - Immich: `http://localhost:2283`
   - Plex: `http://localhost:32400`

### **Immich Storage Shows Wrong Size:**
- This is a known bug. Go to Settings → User Management → Edit your account → Set storage quota to 500GB

### **Plex Not Showing Media:**
- Media libraries need to be set up first
- Contact the server administrator to add your media

### **Slow Performance:**
- Make sure you're on a good internet connection
- Try reducing video quality in Plex settings
- For Immich, check upload quality settings

---

## 🔒 **Security Notes**

- ✅ **All connections are encrypted** via Tailscale
- ✅ **Only family members** with Tailscale access can connect
- ✅ **No data is stored** on external servers
- ✅ **Your photos and media** stay private on your home server

---

## 📞 **Need Help?**

If you run into issues:
1. **Check this guide** first
2. **Restart the apps** (close and reopen)
3. **Check Tailscale connection** (should be green)
4. **Contact the server administrator** for technical issues

---

## 🎉 **You're All Set!**

Your home server is now ready to use! Enjoy:
- 📸 **Automatic photo backup** with Immich
- 🎬 **Streaming your media library** with Plex
- 🔒 **Secure access** from anywhere with Tailscale

**Happy streaming and photo sharing!** 🚀
