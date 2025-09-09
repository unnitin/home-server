# 🌐 Reverse Proxy Setup Guide

Complete guide for setting up Caddy reverse proxy to provide single-URL access to all your home server services.

## 📋 Overview

The reverse proxy provides:
- **🏠 Landing page**: Service dashboard with health indicators
- **🔗 Single domain**: All services under one URL  
- **📱 Clean paths**: `/photos` for Immich, `/plex` for Plex
- **🔒 HTTPS**: Automatic certificates via Tailscale
- **⚡ Performance**: Efficient request routing

**Access pattern**:
- **Homepage**: `https://your-macmini.your-tailnet.ts.net`
- **Immich**: `https://your-macmini.your-tailnet.ts.net/photos`
- **Plex**: `https://your-macmini.your-tailnet.ts.net/plex`

---

## 🚀 Installation

### Automated Setup
```bash
# Install Caddy
./scripts/35_install_caddy.sh

# Enable reverse proxy
./scripts/36_enable_reverse_proxy.sh
```

### What Gets Installed
- **Caddy web server**: Lightweight, automatic HTTPS
- **Landing page**: Service dashboard at document root
- **Caddyfile**: Reverse proxy configuration
- **Homebrew service**: Auto-start on boot

---

## ⚙️ Configuration

### Caddyfile Structure

**Location**: `services/caddy/Caddyfile`

```
:8443 {
  encode zstd gzip
  root * /usr/local/var/www/hakuna_mateti
  file_server

  handle_path /photos* {
    reverse_proxy http://localhost:2283
  }
  handle_path /plex* {
    reverse_proxy http://localhost:32400
  }
}
```

### Landing Page

**Location**: `services/caddy/site/index.html`

**Features**:
- **Service status indicators**: Green/red dots for each service
- **Quick links**: One-click access to web interfaces
- **System information**: Basic server details
- **Responsive design**: Works on desktop and mobile

### Tailscale Integration

**Serve Caddy via HTTPS**:
```bash
sudo tailscale serve --https=443 http://localhost:8443
```

**Replace direct service serving**:
```bash
# Remove direct Immich serving (if previously configured)
sudo tailscale serve --https=443 off

# Serve through Caddy instead
sudo tailscale serve --https=443 http://localhost:8443
```

---

## 🎨 Customizing the Landing Page

### Modify Landing Page

**Edit the homepage**:
```bash
${EDITOR:-nano} services/caddy/site/index.html
```

**Add custom sections**:
```html
<!-- Add after existing service cards -->
<div class="service-card">
  <div class="service-header">
    <div class="service-status status-unknown" id="custom-status"></div>
    <h3>Custom Service</h3>
  </div>
  <p>Your custom service description</p>
  <a href="/custom" class="service-link">Open Custom Service</a>
</div>
```

### Add New Service Routes

**Edit Caddyfile**:
```bash
${EDITOR:-nano} services/caddy/Caddyfile
```

**Add new service**:
```
handle_path /custom* {
  reverse_proxy http://localhost:8080
}
```

**Reload configuration**:
```bash
sudo caddy reload --config services/caddy/Caddyfile
```

### Custom Styling

**Modify CSS**:
```bash
# Landing page includes embedded CSS
${EDITOR:-nano} services/caddy/site/index.html

# Look for <style> section and modify
```

**Add custom logos**:
```bash
# Place images in site directory
cp my-logo.png services/caddy/site/
cp favicon.ico services/caddy/site/

# Reference in HTML
<img src="/my-logo.png" alt="Custom Logo">
```

---

## 🔧 Advanced Configuration

### SSL/TLS Settings

**Caddy handles HTTPS automatically via Tailscale**, but you can customize:

```
:8443 {
  # Custom TLS settings (rarely needed with Tailscale)
  # tls {
  #   protocols tls1.2 tls1.3
  # }
  
  # Security headers
  header {
    Strict-Transport-Security "max-age=31536000; includeSubDomains"
    X-Content-Type-Options "nosniff"
    X-Frame-Options "DENY"
    Referrer-Policy "strict-origin-when-cross-origin"
  }
}
```

### Load Balancing

**For multiple backend instances**:
```
handle_path /app* {
  reverse_proxy {
    to http://localhost:8080
    to http://localhost:8081
    to http://localhost:8082
    lb_policy round_robin
    health_uri /health
  }
}
```

### Authentication

**Basic auth example**:
```
handle_path /admin* {
  basicauth {
    admin $2a$14$hashed_password_here
  }
  reverse_proxy http://localhost:9000
}
```

### Logging

**Custom access logs**:
```
:8443 {
  log {
    output file /opt/homebrew/var/log/caddy_access.log
    format json
  }
}
```

---

## 📱 Mobile App Configuration

### Immich Mobile App

**With reverse proxy**:
- **Server URL**: `https://your-macmini.your-tailnet.ts.net/photos`
- **No port needed**: Uses standard HTTPS

**Benefits**:
- Cleaner URL structure
- Single domain for all services
- Consistent HTTPS experience

### Plex Mobile Apps

**Web access**:
- **URL**: `https://your-macmini.your-tailnet.ts.net/plex`
- **Direct link**: `https://your-macmini.your-tailnet.ts.net/plex/web`

**Native app configuration**:
- Some Plex apps work better with direct access
- Keep both reverse proxy and direct Tailscale serving
- **Fallback option**: `https://your-macmini.your-tailnet.ts.net:32400`

---

## 🔍 Monitoring & Health Checks

### Service Status Monitoring

**Built-in health checks** (landing page):
- JavaScript checks service availability
- Real-time status indicators
- Automatic refresh every 30 seconds

**Manual health checks**:
```bash
# Test proxy routes
curl -f http://localhost:8443/photos
curl -f http://localhost:8443/plex

# Test backend services
curl -f http://localhost:2283
curl -f http://localhost:32400
```

### Performance Monitoring

**Caddy metrics**:
```bash
# Check Caddy status
brew services list | grep caddy

# View access logs
tail -f /opt/homebrew/var/log/caddy.log

# Monitor resource usage
ps aux | grep caddy
```

**Response time testing**:
```bash
# Test proxy performance
time curl -s http://localhost:8443/photos > /dev/null
time curl -s http://localhost:8443/plex > /dev/null

# Compare to direct access
time curl -s http://localhost:2283 > /dev/null
time curl -s http://localhost:32400 > /dev/null
```

---

## 🔧 Troubleshooting

### Reverse Proxy Not Working

**Check Caddy service**:
```bash
brew services list | grep caddy
brew services restart caddy
```

**Validate configuration**:
```bash
caddy validate --config services/caddy/Caddyfile
```

**Check logs**:
```bash
tail -f /opt/homebrew/var/log/caddy.log
```

### Service Routes Not Working

**Test individual components**:
```bash
# 1. Test backend services directly
curl -f http://localhost:2283      # Immich
curl -f http://localhost:32400     # Plex

# 2. Test proxy locally
curl -f http://localhost:8443/photos
curl -f http://localhost:8443/plex

# 3. Test via Tailscale
curl -f https://your-macmini.your-tailnet.ts.net/photos
```

**Common issues**:
- **Backend service down**: Check Immich/Plex health
- **Wrong port**: Verify service ports in Caddyfile
- **Path issues**: Check handle_path directives

### HTTPS Certificate Issues

**Tailscale certificate problems**:
```bash
# Check Tailscale serve status
sudo tailscale serve status

# Reconfigure HTTPS serving
sudo tailscale serve --https=443 http://localhost:8443
```

**Wait for certificate provisioning** (1-2 minutes initial setup)

### Landing Page Not Loading

**Check file permissions**:
```bash
ls -la services/caddy/site/
chmod 644 services/caddy/site/index.html
```

**Check document root**:
```bash
# Verify Caddy can access files
sudo -u _caddy cat services/caddy/site/index.html
```

**Test file serving**:
```bash
curl -f http://localhost:8443/
```

---

## 📈 Performance Optimization

### Caching

**Static file caching**:
```
:8443 {
  header /static/* Cache-Control "public, max-age=31536000"
  
  handle /static/* {
    file_server
  }
}
```

### Compression

**Already enabled** in default config:
```
encode zstd gzip
```

**Custom compression for specific paths**:
```
handle_path /api/* {
  encode gzip
  reverse_proxy http://localhost:2283
}
```

### Connection Optimization

**Keep-alive and timeouts**:
```
handle_path /photos* {
  reverse_proxy http://localhost:2283 {
    header_up X-Forwarded-Proto {scheme}
    header_up X-Forwarded-For {remote_host}
    keepalive 30s
    keepalive_idle_conns 10
  }
}
```

---

## 🔒 Security Considerations

### Header Security

**Security headers** (already included in advanced config):
- **HSTS**: Enforce HTTPS
- **X-Content-Type-Options**: Prevent MIME sniffing
- **X-Frame-Options**: Prevent clickjacking
- **Referrer-Policy**: Control referrer information

### Access Control

**IP-based restrictions** (if needed):
```
@homeusers {
  remote_ip 192.168.1.0/24 100.64.0.0/10
}

handle @homeusers {
  reverse_proxy http://localhost:2283
}

handle {
  respond "Access denied" 403
}
```

### Rate Limiting

**Basic rate limiting**:
```
handle_path /api/* {
  rate_limit {
    zone api_zone 10r/s
  }
  reverse_proxy http://localhost:2283
}
```

---

## 🛠️ Advanced Use Cases

### Multi-Site Setup

**Host multiple domains**:
```
site1.your-tailnet.ts.net {
  reverse_proxy http://localhost:8001
}

site2.your-tailnet.ts.net {
  reverse_proxy http://localhost:8002
}
```

### Development Environment

**Proxy to development servers**:
```
handle_path /dev/* {
  reverse_proxy http://localhost:3000
}

handle_path /api/dev/* {
  reverse_proxy http://localhost:8000
}
```

### Maintenance Mode

**Enable maintenance page**:
```
handle {
  @maintenance file /tmp/maintenance
  handle @maintenance {
    respond "Under maintenance" 503
  }
  
  # Normal proxy rules here
}
```

**Activate maintenance mode**:
```bash
touch /tmp/maintenance
sudo caddy reload --config services/caddy/Caddyfile
```

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](QUICKSTART.md)** - Initial reverse proxy setup
- **📖 [Detailed Setup Guide](SETUP.md)** - Complete installation walkthrough
- **🔒 [Tailscale Setup](TAILSCALE.md)** - HTTPS certificate configuration
- **🎬 [Plex Setup](PLEX.md)** - Plex reverse proxy configuration
- **📸 [Immich Setup](IMMICH.md)** - Immich reverse proxy configuration
- **🔧 [Troubleshooting](TROUBLESHOOTING.md)** - Reverse proxy troubleshooting

---

**Need help?** Check the [🔧 Troubleshooting Guide](TROUBLESHOOTING.md) or test individual components with `curl` commands above.
