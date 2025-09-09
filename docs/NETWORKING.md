# 🌐 Networking Architecture

This document explains how the home server's networking, DNS resolution, and HTTPS serving work together to provide secure, seamless access to your services.

## 🔍 Overview

The networking setup combines **Tailscale's mesh VPN** with **MagicDNS** to create a secure, encrypted tunnel that works from anywhere while providing clean, certificate-secured URLs.

```
Your Device → Tailscale Tunnel → Mac Mini → Local Services
           ↑ (encrypted)      ↑ (HTTPS)   ↑ (HTTP)
```

## 🏗️ Architecture Components

### **1. Tailscale Mesh Network**
- **Purpose**: Secure, encrypted tunnel between your devices
- **IP Range**: `100.x.x.x` (CGNAT range, not routable on internet)
- **Protocols**: WireGuard-based, automatic NAT traversal
- **Security**: Zero-trust network, devices must be authenticated

### **2. MagicDNS Resolution**
- **Purpose**: Resolve friendly domain names to Tailscale IPs
- **DNS Server**: `100.100.100.100` (Tailscale's DNS)
- **Domain Format**: `device-name.tailnet-id.ts.net`
- **Example**: `your-device.your-tailnet.ts.net` → `100.121.184.93`

### **3. HTTPS Serving**
- **Purpose**: Provide valid SSL certificates for web services
- **Certificates**: Automatically managed by Tailscale
- **Protocols**: HTTP/2, TLS 1.3
- **Domains**: Only works with properly resolved domain names

## 🔄 Request Flow

### **Complete Request Journey**:

```
1. User types: https://your-device.your-tailnet.ts.net
2. DNS Query: Device → Tailscale DNS (100.100.100.100)
3. DNS Response: your-device.your-tailnet.ts.net → 100.121.184.93
4. Connection: Device → Tailscale tunnel → Mac Mini (100.121.184.93:443)
5. HTTPS Termination: Tailscale validates certificate, establishes TLS
6. Proxy: Tailscale → http://localhost:2283 (Immich)
7. Response: Immich → Tailscale → Device (encrypted tunnel)
```

## ⚙️ DNS Configuration

### **Problem Solved**
macOS networking sometimes ignores Tailscale's DNS configuration, causing domain resolution to fail. This prevents HTTPS serving from working.

### **Solution Applied**
```bash
# Set Tailscale DNS as primary, Cloudflare as fallback
sudo networksetup -setdnsservers "Wi-Fi" 100.100.100.100 1.1.1.1

# Flush caches to apply immediately
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### **Why This Works**
- **Primary**: `100.100.100.100` resolves `*.ts.net` domains to Tailscale IPs
- **Fallback**: `1.1.1.1` handles all other domains (faster than ISP DNS)
- **System-wide**: All applications use these DNS servers

## 🔒 Security Model

### **Network Isolation**
```
Internet Users → 🚫 Cannot reach 100.121.184.93
                     (Tailscale IPs not routable)

Tailscale Users → ✅ Can reach 100.121.184.93
                      (Authenticated mesh network)
```

### **Certificate Security**
- **Issuer**: Tailscale (trusted by all major browsers)
- **Validation**: Domain ownership verified via Tailscale control plane
- **Renewal**: Automatic, no manual intervention required
- **Scope**: Valid only for devices on your Tailscale network

### **Transport Security**
- **Tunnel**: WireGuard encryption (ChaCha20Poly1305)
- **HTTPS**: TLS 1.3 with perfect forward secrecy
- **Authentication**: Device keys + user authentication required

## 📱 Device Configuration

### **macOS/iOS**
- Install Tailscale app from App Store
- Authenticate with your account
- DNS automatically configured (or use manual config if issues)

### **Android**
- Install Tailscale from Google Play
- Enable "Use Tailscale DNS" in settings
- Grant VPN permissions

### **Windows/Linux**
- Install Tailscale client
- Run: `tailscale up --accept-dns`
- Verify DNS with: `nslookup your-device.your-tailnet.ts.net`

## 🛠️ Service Configuration

### **Immich (Photos)**
```bash
# HTTPS serving on port 443
sudo tailscale serve --bg --https=443 http://localhost:2283

# Accessible at:
https://your-device.your-tailnet.ts.net
```

### **Plex (Media)**
```bash
# HTTPS serving on port 32400
sudo tailscale serve --bg --https=32400 http://localhost:32400

# Accessible at:
https://your-device.your-tailnet.ts.net:32400
```

### **Port Mapping**
- **Local Service**: `http://localhost:2283` (Immich)
- **Tailscale Serve**: `https://domain:443` → proxy to localhost:2283
- **Result**: Secure HTTPS with valid certificates

## 🔧 Troubleshooting

### **DNS Resolution Issues**
```bash
# Test DNS resolution
nslookup your-device.your-tailnet.ts.net

# Expected output:
Server:         100.100.100.100
Address:        100.100.100.100#53
Name:   nitins-mac-mini.tailb6b278.ts.net
Address: 100.121.184.93
```

### **HTTPS Connection Issues**
```bash
# Test HTTPS connectivity
curl -I https://your-device.your-tailnet.ts.net

# Expected output:
HTTP/2 404 
content-type: application/json; charset=utf-8
```

### **Common Fixes**

#### **"Could not resolve host"**
```bash
# Check DNS servers
scutil --dns | grep nameserver

# Fix DNS configuration
sudo networksetup -setdnsservers "Wi-Fi" 100.100.100.100 1.1.1.1
sudo dscacheutil -flushcache
```

#### **"Connection refused"**
```bash
# Check Tailscale serve status
sudo tailscale serve status

# Reconfigure if needed
sudo tailscale serve --bg --https=443 http://localhost:2283
```

#### **Certificate errors**
```bash
# Check Tailscale authentication
tailscale status

# Re-authenticate if needed
sudo tailscale up --accept-dns=true
```

## 📊 Network Monitoring

### **Check Network Health**
```bash
# Tailscale connectivity
tailscale netcheck

# DNS resolution test
dig @100.100.100.100 your-device.your-tailnet.ts.net

# Service availability
./diagnostics/network_port_check.sh localhost 2283
```

### **Performance Monitoring**
- **Latency**: Monitor DERP server latency in `tailscale netcheck`
- **Bandwidth**: Tailscale uses minimal overhead for small requests
- **Battery**: Tailscale is optimized for mobile device battery life

## 🌍 Remote Access Scenarios

### **Home Network**
- **Direct connection**: If both devices on same LAN
- **Fallback**: Tailscale tunnel if direct fails
- **Performance**: Near-native speed

### **Mobile/Cellular**
- **Connection**: Always via Tailscale DERP servers
- **Latency**: +10-50ms depending on nearest DERP
- **Reliability**: Works on any internet connection

### **Corporate/Restricted Networks**
- **Firewall traversal**: Tailscale handles automatically
- **Port blocking**: Uses HTTPS/443 which is rarely blocked
- **VPN conflicts**: Tailscale works alongside most corporate VPNs

## 🔮 Advanced Configuration

### **Custom Domain (Future)**
You can configure custom domains that point to your Tailscale IPs:
```bash
# Example: photos.yourdomain.com → nitins-mac-mini.tailb6b278.ts.net
# Requires DNS CNAME record and Tailscale certificate configuration
```

### **Load Balancing (Scaling)**
Multiple Mac Minis can share the same Tailscale network:
```bash
# Each device gets unique Tailscale IP and hostname
mini-1.tailb6b278.ts.net → 100.121.184.93
mini-2.tailb6b278.ts.net → 100.121.184.94
```

### **Network Segmentation**
Tailscale ACLs can restrict access between devices:
```json
{
  "acls": [
    {"action": "accept", "src": ["mobile-devices"], "dst": ["home-servers:443,32400"]}
  ]
}
```

---

## 📚 Additional Resources

- [**Tailscale Documentation**](https://tailscale.com/kb/)
- [**MagicDNS Guide**](https://tailscale.com/kb/1081/magicdns/)
- [**HTTPS Certificates**](https://tailscale.com/kb/1153/enabling-https/)
- [**Troubleshooting DNS**](https://tailscale.com/kb/1188/debug-dns/)

**Questions?** Check the main [**🆘 Troubleshooting Guide**](TROUBLESHOOTING.md) or run the diagnostics suite: `./diagnostics/run_all.sh`
