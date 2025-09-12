# Future Extensions

This document outlines potential enhancements and extensions for the `mac-mini-homeserver` setup that can be implemented in the future.

## 🌐 Custom Domain Names

### Overview
Replace Tailscale's default domain format (`device.tailnet.ts.net`) with user-friendly custom domains like `photos.yourdomain.com`.

### End Result Examples
- **Current**: `https://nitins-mac-mini.tailb6b278.ts.net`
- **With Custom Domain**: `https://photos.srivastava.family`

### Benefits
- ✅ **Professional URLs**: Easy to remember and share
- ✅ **Branded Experience**: Use your family name or creative domains
- ✅ **Service-Specific Subdomains**: Each service gets its own clean URL
- ✅ **Mobile App Compatibility**: Cleaner server URLs in mobile apps

### Implementation Steps

#### 1. Domain Registration
- **Cost**: ~$10-15/year
- **Registrars**: Namecheap, GoDaddy, Cloudflare, etc.
- **Recommended TLDs**: `.family`, `.home`, `.tech`, or your personal domain

#### 2. DNS Configuration
```bash
# Example DNS records (A records pointing to Tailscale IP)
photos.yourdomain.com    → 100.121.184.93
plex.yourdomain.com      → 100.121.184.93
home.yourdomain.com      → 100.121.184.93
```

#### 3. Tailscale Certificate Configuration
```bash
# Request certificates for custom domains
sudo tailscale cert photos.yourdomain.com
sudo tailscale cert plex.yourdomain.com
```

#### 4. Reverse Proxy Updates
Update `services/caddy/Caddyfile`:
```caddyfile
photos.yourdomain.com {
    reverse_proxy localhost:2283
}

plex.yourdomain.com {
    reverse_proxy localhost:32400
}

home.yourdomain.com {
    root * /opt/homebrew/var/www/hakuna_mateti
    file_server
}
```

#### 5. DNS Resolver Updates
```bash
# Add custom domain resolver
echo -e "nameserver 100.100.100.100\nport 53" | sudo tee /etc/resolver/yourdomain.com
```

### Alternative Approaches

#### Option A: Subdomain Structure
- `immich.home.yourdomain.com`
- `plex.home.yourdomain.com` 
- `dashboard.home.yourdomain.com`

#### Option B: Service-Specific Domains
- `photos.yourdomain.com` (Immich)
- `media.yourdomain.com` (Plex)
- `hub.yourdomain.com` (Dashboard)

#### Option C: Single Domain with Paths
- `yourdomain.com/photos` → Immich
- `yourdomain.com/plex` → Plex
- `yourdomain.com/` → Dashboard

### Required Script Updates

#### New Script: `scripts/95_configure_custom_domain.sh`
```bash
#!/usr/bin/env bash
# Configure custom domain for homeserver services

# Validate domain ownership
# Request Tailscale certificates
# Update Caddy configuration
# Configure DNS resolvers
# Test custom domain access
```

#### Updated Scripts
- `scripts/91_configure_https_dns.sh`: Add custom domain resolver support
- `scripts/37_enable_simple_landing.sh`: Support custom domain configuration
- `docs/NETWORKING.md`: Document custom domain architecture

### Security Considerations
- **DNS Security**: Use DNSSEC where supported
- **Certificate Management**: Automatic renewal via Tailscale
- **Access Control**: Maintain Tailscale network isolation
- **Domain Privacy**: Consider domain privacy protection

### Cost Analysis
| Component | Cost | Frequency |
|-----------|------|-----------|
| Domain Registration | $10-15 | Annual |
| DNS Service (Cloudflare) | Free | - |
| SSL Certificates | Free (via Tailscale) | - |
| **Total** | **~$1-2/month** | - |

### Testing Strategy
1. **Domain Validation**: Verify domain ownership and DNS propagation
2. **Certificate Testing**: Ensure SSL certificates are properly issued
3. **Service Access**: Test all services via custom domains
4. **Mobile Apps**: Verify mobile app connectivity with custom URLs
5. **Failover**: Ensure Tailscale fallback works if custom DNS fails

### Documentation Updates
- Update README.md with custom domain option
- Create setup guide for domain configuration
- Update mobile app setup instructions
- Document troubleshooting for custom domains

---

## 🔄 Other Future Extensions

### Remote Access via Internet (Tailscale Funnel)
- **Purpose**: Share services with users outside your Tailscale network
- **Use Case**: Share photo albums with extended family
- **Implementation**: `tailscale funnel` commands

### Multi-Device Setup
- **Purpose**: Distribute services across multiple devices
- **Architecture**: Load balancing, redundancy
- **Services**: Separate storage, compute, and access layers

### Backup and Disaster Recovery
- **Cloud Backup**: Automated backup to cloud storage
- **RAID Monitoring**: Advanced RAID health monitoring
- **Service Recovery**: Automated service restoration

### Advanced Media Management
- **Media Acquisition**: Automated media downloading (Sonarr, Radarr)
- **Media Organization**: Advanced file organization and metadata
- **Streaming Optimization**: Transcoding and bandwidth management

### Home Automation Integration
- **Smart Home Hub**: Integrate with HomeKit, Home Assistant
- **IoT Device Management**: Manage smart home devices
- **Automation Rules**: Automated actions based on conditions

### Monitoring and Observability
- **Service Monitoring**: Uptime monitoring and alerting
- **Performance Metrics**: Resource usage tracking
- **Log Aggregation**: Centralized logging and analysis
- **Dashboard**: Real-time system status dashboard
