#!/usr/bin/env bash
# Configure Tailscale HTTPS serving with DNS fix
# This script resolves DNS resolution issues and sets up secure HTTPS access

set -euo pipefail

source "$(dirname "$0")/_compose.sh"

banner "Configuring Tailscale HTTPS with DNS Fix"

# Check if Tailscale is installed and running
if ! command -v tailscale >/dev/null 2>&1; then
    echo "ERROR: Tailscale not found. Please run scripts/90_install_tailscale.sh first"
    exit 1
fi

# Check Tailscale status
if ! tailscale status >/dev/null 2>&1; then
    echo "ERROR: Tailscale not connected. Please run: sudo tailscale up --accept-dns=true"
    exit 1
fi

# Get current Tailscale IP and hostname
TAILSCALE_IP=$(tailscale status --json | grep -A1 '"TailscaleIPs"' | grep -o '"[0-9.]*"' | tr -d '"' | head -1 || echo "")
TAILSCALE_HOSTNAME=$(tailscale status --json | grep '"DNSName"' | cut -d'"' -f4 | sed 's/\.$//' || echo "")

if [[ -z "$TAILSCALE_IP" || -z "$TAILSCALE_HOSTNAME" ]]; then
    echo "ERROR: Could not determine Tailscale IP or hostname"
    exit 1
fi

echo "Tailscale IP: $TAILSCALE_IP"
echo "Tailscale Hostname: $TAILSCALE_HOSTNAME"

# Detect active network interface
NETWORK_INTERFACE=""
if networksetup -getairportnetwork en0 >/dev/null 2>&1; then
    NETWORK_INTERFACE="Wi-Fi"
elif networksetup -getinfo "Ethernet" | grep -q "IP address:"; then
    NETWORK_INTERFACE="Ethernet"
elif networksetup -getinfo "USB 10/100/1000 LAN" | grep -q "IP address:"; then
    NETWORK_INTERFACE="USB 10/100/1000 LAN"
else
    echo "ERROR: Could not determine active network interface"
    exit 1
fi

echo "Active network interface: $NETWORK_INTERFACE"

# Check current DNS servers
echo "Current DNS servers:"
networksetup -getdnsservers "$NETWORK_INTERFACE" || echo "No DNS servers set"

# Configure DNS servers (Tailscale DNS + Cloudflare fallback)
echo "Configuring DNS servers..."
sudo networksetup -setdnsservers "$NETWORK_INTERFACE" 100.100.100.100 1.1.1.1

# Flush DNS cache
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Wait for DNS to propagate
sleep 3

# Test DNS resolution
echo "Testing DNS resolution..."
if nslookup "$TAILSCALE_HOSTNAME" | grep -q "100.100.100.100"; then
    echo "SUCCESS: DNS resolution working via Tailscale DNS"
else
    echo "WARNING: DNS may not be fully working yet, continuing..."
fi

# Configure HTTPS serving for Immich
echo "Configuring HTTPS serving for Immich..."
sudo tailscale serve --bg --https=443 http://localhost:2283

# Configure HTTPS serving for Plex (if running)
if curl -s -o /dev/null -w "%{http_code}" http://localhost:32400 | grep -q "401\|302"; then
    echo "Configuring HTTPS serving for Plex..."
    sudo tailscale serve --bg --https=32400 http://localhost:32400
else
    echo "WARNING: Plex not detected on port 32400, skipping HTTPS configuration"
fi

# Show serve status
echo "Current Tailscale serve configuration:"
sudo tailscale serve status

# Test HTTPS URLs
echo "Testing HTTPS URLs..."
echo
echo "SECURE HTTPS URLS:"
echo "Immich (Photos): https://$TAILSCALE_HOSTNAME"
if sudo tailscale serve status | grep -q ":32400"; then
    echo "Plex (Media): https://$TAILSCALE_HOSTNAME:32400"
fi
echo
echo "Mobile Apps:"
echo "Immich Server: https://$TAILSCALE_HOSTNAME"
if sudo tailscale serve status | grep -q ":32400"; then
    echo "Plex Server: https://$TAILSCALE_HOSTNAME:32400"
fi

# Test connectivity
if curl -s -I "https://$TAILSCALE_HOSTNAME" | grep -q "HTTP/2"; then
    echo "SUCCESS: HTTPS serving is working! (HTTP/2 detected)"
else
    echo "WARNING: HTTPS may need a moment to become available"
fi

echo
echo "SUCCESS: Tailscale HTTPS configuration complete!"
echo "Your services are now accessible via secure HTTPS URLs from any device on your Tailscale network."
