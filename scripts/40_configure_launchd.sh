#!/usr/bin/env bash
set -euo pipefail

# Refuse root — per-user LaunchAgents only
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Run as your user (not sudo)."; exit 2
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="$ROOT/launchd"

mkdir -p "$PLIST_DIR"

# Install plist from template with variable substitution
install_plist() {
  local service_name="$1"
  local template_plist="$TEMPLATE_DIR/io.homelab.${service_name}.plist"
  local target_plist="$PLIST_DIR/io.homelab.${service_name}.plist"
  
  echo "📦 Installing service: io.homelab.${service_name}"
  
  # Check if template exists
  if [[ ! -f "$template_plist" ]]; then
    echo "⚠️  Template not found: $template_plist"
    return 1
  fi
  
  # Copy template and substitute variables
  cp "$template_plist" "$target_plist"
  
  # Replace template variables
  sed -i '' "s|__HOME__|$HOME|g" "$target_plist"
  sed -i '' "s|__USER__|$(whoami)|g" "$target_plist"
  
  echo "   ✅ Template processed: $target_plist"
  return 0
}

# Bootstrap (load and enable) a LaunchD service
bootstrap() {
  local service_name="$1"
  local plist="$PLIST_DIR/io.homelab.${service_name}.plist"
  local label="io.homelab.${service_name}"
  
  echo "🚀 Bootstrapping service: $label"
  
  # Unload existing service (ignore errors)
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  
  # Load and enable new service
  if launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
    if launchctl enable "gui/$(id -u)/$label" 2>/dev/null; then
      echo "   ✅ Service active: $label"
    else
      echo "   ⚠️  Enable failed: $label"
    fi
  else
    echo "   ❌ Bootstrap failed: $label"
  fi
}

echo "=== Installing Enhanced Recovery Automation ==="
echo "📁 Templates: $TEMPLATE_DIR"
echo "🎯 Target: $PLIST_DIR"
echo ""

# Define services in dependency order (storage first, then infrastructure, then applications)
SERVICES=(
  "storage"       # Mount points and storage configuration
  "powermgmt"     # Power management for 24/7 server operation
  "colima"        # Docker runtime for Immich
  "compose.immich" # Immich containers
  "plex"          # Plex Media Server
  "landing"       # Landing page + Tailscale serving
  "tailscale"     # Tailscale VPN connection
  "updatecheck"   # System update monitoring
)

# Install and bootstrap each service
INSTALLED=0
FAILED=0

for service in "${SERVICES[@]}"; do
  echo "--- Processing: $service ---"
  
  if install_plist "$service"; then
    if bootstrap "$service"; then
      ((INSTALLED++))
    else
      ((FAILED++))
    fi
  else
    echo "   ⚠️  Skipping bootstrap (template missing)"
    ((FAILED++))
  fi
  echo ""
done

echo "=== Installation Complete ==="
echo "✅ Successfully installed: $INSTALLED services"
echo "❌ Failed installations: $FAILED services"
echo ""

if [[ $INSTALLED -gt 0 ]]; then
  echo "📋 View service status:"
  echo "   launchctl list | grep homelab"
  echo ""
  echo "📄 Monitor logs during restart:"
  echo "   tail -f /tmp/{storage,colima,immich,plex,landing}.{out,err}"
  echo ""
  echo "🔄 Enhanced automation ready for graceful recovery!"
else
  echo "⚠️  No services were successfully installed."
  exit 1
fi
