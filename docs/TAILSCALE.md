# 🔒 Tailscale Setup & Usage Guide

Complete guide for setting up secure remote access to your Mac mini home server using Tailscale mesh VPN with HTTPS certificates.

## 📋 Overview

Tailscale creates a secure, encrypted mesh network that lets you access your home server from anywhere without port forwarding or VPN configuration. Features include:

- **Zero-config VPN**: Automatic peer-to-peer connections
- **HTTPS certificates**: Automatic TLS for your services  
- **No open ports**: No router configuration needed
- **Multi-platform**: Works on all devices
- **Access control**: Fine-grained permissions

---

## 🚀 Installation

### Automated Installation
```bash
./scripts/90_install_tailscale.sh
```

### What Gets Installed
- **Tailscale client**: CLI and system service
- **LaunchDaemon**: Auto-start on boot *(if launchd configured)*
- **DNS integration**: MagicDNS for easy hostnames

### Manual Installation
1. Download from [tailscale.com](https://tailscale.com/download)
2. Install the `.pkg` file
3. Or use Homebrew: `brew install tailscale`

---

## ⚙️ Initial Setup

### 1. Connect to Network
```bash
sudo tailscale up --accept-dns=true
```

**What this does**:
- Opens browser for account authentication
- Connects your Mac to your Tailscale network (tailnet)
- Enables MagicDNS for easy hostnames
- Registers the device with a stable hostname

### 2. Verify Connection
```bash
# Check status
tailscale status

# Get your IP and hostname
tailscale ip
tailscale hostname
```

**Expected output**:
```
your-macmini   [YOUR-IP]     macOS   active; direct [RELAY-IP]:41641
```

### 3. Configure Services

**Enable HTTPS serving for direct access**:
```bash
# Immich (photos)
sudo tailscale serve --https=443 http://localhost:2283

# Plex (media)  
sudo tailscale serve --https=32400 http://localhost:32400
```

---

## 🌐 Service Access URLs

### Direct Service Access

**Immich (Photos)**:
- **URL**: `https://your-macmini.your-tailnet.ts.net`
- **Port**: 443 (standard HTTPS)
- **Mobile apps**: Use this URL in server settings

**Plex (Media)**:
- **URL**: `https://your-macmini.your-tailnet.ts.net:32400`
- **Port**: 32400 (Plex standard)
- **Mobile apps**: Use this URL without `https://`

### With Reverse Proxy (Optional)

**Enable reverse proxy first**:
```bash
./scripts/35_install_caddy.sh
./scripts/36_enable_reverse_proxy.sh
```

**Then serve Caddy instead**:
```bash
# Replace direct Immich serving
sudo tailscale serve --https=443 http://localhost:8443
```

**Access URLs**:
- **Landing page**: `https://your-macmini.your-tailnet.ts.net`
- **Immich**: `https://your-macmini.your-tailnet.ts.net/photos`
- **Plex**: `https://your-macmini.your-tailnet.ts.net/plex`

---

## 📱 Mobile Device Setup

### iOS/Android Setup

1. **Install Tailscale app** from App Store/Google Play
2. **Sign in** with same account used for server
3. **Connect** - device joins your tailnet automatically
4. **Access services** using server URLs

### Mobile App Configuration

**Immich Mobile App**:
- **Server URL**: `https://your-macmini.your-tailnet.ts.net`
- **No port needed**: Uses standard HTTPS (443)
- **Auto-sync**: Works over cellular and WiFi

**Plex Mobile App**:
- **Manual server**: `your-macmini.your-tailnet.ts.net:32400`
- **Or automatic**: Plex often finds the server automatically
- **Quality settings**: Configure for mobile data usage

### Desktop/Laptop Setup

**Install Tailscale**:
- Download client for your OS from [tailscale.com](https://tailscale.com/download)
- Sign in with same account
- Access services via browser using server URLs

---

## 🔧 Advanced Configuration

### Custom Hostnames

**Set custom hostname**:
```bash
sudo tailscale up --hostname=homeserver --accept-dns=true
```

**Benefits**:
- Cleaner URLs: `https://homeserver.your-tailnet.ts.net`
- Easier to remember
- More professional appearance

### Exit Node (Optional)

**Enable your Mac as exit node**:
```bash
sudo tailscale up --advertise-exit-node --accept-dns=true
```

**What this enables**:
- Route all internet traffic through your home server
- Useful when traveling on untrusted networks
- Access geo-restricted content from home location

**Use exit node from other devices**:
- Enable in Tailscale app settings
- Select your Mac mini as exit node

### Subnet Routing

**Advertise local network**:
```bash
# Example: Share access to 192.168.1.0/24 network
sudo tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=true
```

**Enable in Tailscale admin**:
1. Go to [tailscale.com/admin](https://tailscale.com/admin)
2. Find your Mac mini device
3. **Enable subnet routes**: Approve the advertised routes

**Benefits**:
- Access other devices on home network remotely
- Reach printers, NAS, IoT devices
- No need for individual Tailscale on every device

---

## 🛡️ Security & Access Control

### Access Control Lists (ACLs)

**Basic ACL example**:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:family"],
      "dst": ["tag:homeserver:*"]
    }
  ],
  "tagOwners": {
    "tag:family": ["your-email@example.com"],
    "tag:homeserver": ["your-email@example.com"]
  }
}
```

**Apply ACLs**:
1. Go to [tailscale.com/admin](https://tailscale.com/admin)
2. **Access Controls** → **Edit ACLs**
3. Define rules for device access

### Device Management

**Device authorization**:
- **Auto-approve**: Devices auto-join (convenient)
- **Manual approval**: Require approval for new devices (secure)
- **Key expiry**: Set device key expiration times

**Remove compromised devices**:
1. Tailscale admin console
2. Find device in device list
3. **Delete** or **Disable** device

### SSH Access

**Enable SSH over Tailscale**:
```bash
sudo tailscale up --ssh --accept-dns=true
```

**Benefits**:
- SSH access from any Tailscale device
- No password required (uses Tailscale identity)
- Audit logs in Tailscale console

**Access from other devices**:
```bash
ssh your-macmini.your-tailnet.ts.net
```

---

## 🔍 Monitoring & Diagnostics

### Status Checks
```bash
# Detailed status
tailscale status

# Network info
tailscale netcheck

# Ping other devices
tailscale ping other-device.your-tailnet.ts.net
```

### Connection Quality

**Check connection type**:
- **Direct**: Best performance, peer-to-peer
- **DERP relay**: Fallback through Tailscale servers
- **Relay location**: Geographic location of relay

**Improve connections**:
- Enable UPnP/NAT-PMP on router
- Configure firewall to allow UDP 41641
- Use `tailscale netcheck` to diagnose issues

### Logs and Debugging

**View logs**:
```bash
# System logs (macOS)
log show --predicate 'subsystem == "com.tailscale.ipn"' --last 1h

# Tailscale daemon logs
sudo tailscale debug daemon-logs
```

**Debug connectivity**:
```bash
# Network map
tailscale debug netmap

# DNS resolution
tailscale debug dns
```

---

## 🔧 Troubleshooting

### Common Issues

**Can't connect to tailnet**:
1. Check internet connectivity
2. Verify account authentication: `tailscale logout && tailscale up`
3. Check firewall settings
4. Try different network (mobile hotspot)

**Services not accessible**:
1. Verify Tailscale serve status: `sudo tailscale serve status`
2. Test local access first: `curl http://localhost:2283`
3. Check service is running: `./diagnostics/check_docker_services.sh`
4. Verify HTTPS certificates are ready (can take a few minutes)

**Slow connections**:
1. Check connection type: `tailscale status`
2. If using DERP relay, try different network
3. Configure router for better NAT traversal
4. Check for local network issues

**Mobile app issues**:
1. Ensure mobile device is connected to Tailscale
2. Verify server URL in app settings
3. Check for app updates
4. Try different network (WiFi vs cellular)

### Performance Optimization

**Direct connections**:
- Configure router UPnP for better NAT traversal
- Use wired connection when possible
- Minimize network hops

**HTTPS certificate delays**:
- Initial certificate provisioning takes 1-2 minutes
- Subsequent connections are immediate
- Certificates auto-renew

### Recovery Procedures

**Reset Tailscale connection**:
```bash
sudo tailscale down
sudo tailscale up --reset --accept-dns=true
```

**Complete reinstall**:
```bash
# Remove Tailscale
sudo /Applications/Tailscale.app/Contents/MacOS/Tailscale down
sudo rm -rf /Library/Tailscale

# Reinstall
brew install tailscale
sudo tailscale up --accept-dns=true
```

---

## 📈 Advanced Features

### Magic DNS

**Custom DNS names**:
- Devices get automatic names: `device-name.your-tailnet.ts.net`
- Works across all devices in tailnet
- No manual DNS configuration needed

**Split DNS**:
- Route specific domains through Tailscale
- Useful for accessing internal services
- Configure in Tailscale admin console

### Taildrop (File Sharing)

**Send files between devices**:
```bash
# Send file to another device
tailscale file cp myfile.txt other-device:

# Receive files
tailscale file get
```

**GUI integration**:
- Drag and drop in Tailscale apps
- Share from mobile apps directly
- Cross-platform file sharing

### API Integration

**Use Tailscale API**:
- Manage devices programmatically
- Automate ACL updates
- Monitor network status

**Example API calls**:
```bash
# Get device list (requires API key)
curl -H "Authorization: Bearer $TAILSCALE_API_KEY" \
     https://api.tailscale.com/api/v2/tailnet/$TAILNET/devices
```

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](QUICKSTART.md)** - Get Tailscale running quickly
- **📖 [Detailed Setup Guide](SETUP.md)** - Complete installation walkthrough
- **🌐 [Reverse Proxy Setup](REVERSE-PROXY.md)** - Single URL access configuration
- **🎬 [Plex Setup](PLEX.md)** - Plex remote access configuration
- **📸 [Immich Setup](IMMICH.md)** - Photo management remote access
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or test connectivity with `tailscale netcheck`.
