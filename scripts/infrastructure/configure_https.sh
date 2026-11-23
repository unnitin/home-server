#!/usr/bin/env bash
# Configure Tailscale HTTPS serving with DNS fix
# This script resolves DNS resolution issues and sets up secure HTTPS access

set -euo pipefail

# Simple banner function
banner() { echo; echo "=== $* ==="; }

banner "Configuring Tailscale HTTPS with DNS Fix"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/tailscale.sh
source "$SCRIPT_DIR/lib/tailscale.sh"

# Check if Tailscale is installed and running (the Mac app's CLI isn't on PATH;
# tailscale_cli finds it)
if ! tailscale_cli >/dev/null; then
    echo "ERROR: Tailscale not found. Please run scripts/infrastructure/install_tailscale.sh first"
    exit 1
fi

# Check Tailscale status
if ! ts status >/dev/null 2>&1; then
    echo "ERROR: Tailscale not connected. Open the Tailscale app, or run: tailscale up --accept-dns=true"
    exit 1
fi

# Get current Tailscale IP and hostname
TAILSCALE_IP=$(ts ip -4 2>/dev/null | head -1 || echo "")
TAILSCALE_HOSTNAME=$(ts_hostname)

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

# Create domain-specific resolver for .ts.net domains (permanent fix for macOS DNS issues)
echo "Configuring domain-specific DNS resolver for .ts.net..."
sudo mkdir -p /etc/resolver
echo -e "nameserver 100.100.100.100\nport 53" | sudo tee /etc/resolver/ts.net >/dev/null

# Flush DNS cache
echo "Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Wait for DNS to propagate
sleep 3

# Test DNS resolution
echo "Testing DNS resolution..."
if ping -c 1 "$TAILSCALE_HOSTNAME" >/dev/null 2>&1; then
    echo "SUCCESS: DNS resolution working for Tailscale domains"
else
    echo "WARNING: DNS may not be fully working yet, continuing..."
fi

# Configure HTTPS serving. One list of mappings (config/tailscale_serve.txt) for
# every service; this script used to point 443 at Immich while enable_landing.sh
# pointed it at the landing page, so the result depended on which ran last.
echo "Applying tailnet HTTPS mappings from config/tailscale_serve.txt..."
"$SCRIPT_DIR/apply_tailscale_serve.sh" --wait 30 || echo "WARNING: some mappings were not applied; re-run scripts/infrastructure/apply_tailscale_serve.sh"

# Show serve status
echo "Current Tailscale serve configuration:"
ts serve status || true

echo
echo "SECURE HTTPS URLS (tailnet only):"
echo "Landing page:    https://$TAILSCALE_HOSTNAME"
echo "Immich (Photos): https://$TAILSCALE_HOSTNAME:2283"
echo "Plex (Media):    https://$TAILSCALE_HOSTNAME:32400"
echo "Jellyfin:        https://$TAILSCALE_HOSTNAME:8096"
echo
echo "Mobile Apps:"
echo "Immich Server: https://$TAILSCALE_HOSTNAME:2283"

# Test connectivity
if curl -s -I "https://$TAILSCALE_HOSTNAME" | grep -q "HTTP/2"; then
    echo "SUCCESS: HTTPS serving is working! (HTTP/2 detected)"
else
    echo "WARNING: HTTPS may need a moment to become available"
fi

echo
echo "SUCCESS: Tailscale HTTPS configuration complete!"
echo "Your services are now accessible via secure HTTPS URLs from any device on your Tailscale network."
