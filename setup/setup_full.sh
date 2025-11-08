#!/usr/bin/env bash
set -euo pipefail

# --- Self-heal executable bits (safe to run even if already set) ---
_THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
_REPO_ROOT="$(cd "$_THIS_DIR/.." && pwd)"

# Ensure all scripts under setup/, scripts/, diagnostics/ are executable
find "$_REPO_ROOT/setup" "$_REPO_ROOT/scripts" "$_REPO_ROOT/diagnostics" \
  -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Resolve repo root and continue with existing flow
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

banner(){ echo; echo "=== $* ==="; }
confirm(){
  read -r -p "$1 [y/N] " a || true
  case "$a" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *)                 return 1 ;;
  esac
}

banner "Bootstrap"
setup/setup.sh

banner "Colima & Docker"
scripts/infrastructure/install_docker.sh
scripts/infrastructure/start_docker.sh

banner "Storage (DESTRUCTIVE)"
echo "Set SSD_DISKS/NVME_DISKS/COLD_DISKS and RAID_I_UNDERSTAND_DATA_LOSS=1 if you want to (re)build."
echo "Optional: set CLEAN_BEFORE_RAID=1 to wipe old AppleRAID sets & GPT on the target disks before creating."

read -r -p "Proceed to (re)build arrays now? [y/N] " a; case "$a" in
  [yY]* )
    # Optional pre-clean (DESTRUCTIVE)—only runs if CLEAN_BEFORE_RAID=1
    scripts/storage/preclean_disks.sh

    # If you want trace logs, run this setup with: DEBUG=1 ./setup/setup_full.sh
    if [[ "${DEBUG:-0}" == "1" ]]; then set -x; fi
    echo "🔧 Creating RAID arrays and mounting storage..."
    if ! {
      [[ -n "${SSD_DISKS:-}"  ]] && scripts/storage/create_ssd_raid.sh
      [[ -n "${NVME_DISKS:-}" ]] && scripts/storage/create_nvme_raid.sh  
      [[ -n "${COLD_DISKS:-}" ]] && scripts/storage/create_hdd_raid.sh
      echo "🔧 Configuring mount points and services..."
      scripts/storage/format_and_mount.sh
    } 2>&1 | tee /tmp/homelab_storage.log ; then
      echo "❌ Storage setup failed. See /tmp/homelab_storage.log for details."
      echo "💡 Common fixes:"
      echo "   - Ensure RAID_I_UNDERSTAND_DATA_LOSS=1 is set"
      echo "   - Check disk identifiers with: diskutil list"
      echo "   - Verify no other processes are using the disks"
      exit 1
    fi
    
    echo "✅ Storage setup completed successfully!"
    if [[ "${DEBUG:-0}" == "1" ]]; then set +x; fi
    ;;
  * )
    echo "Skipping destructive storage step."
    ;;
esac

banner "Storage Directory Structure"
echo "Setting up direct mount directory structure for services..."
echo "Note: This step requires sudo permissions to create directories in /Volumes/"
sudo scripts/storage/setup_direct_mounts.sh

banner "Immich"
if [[ ! -f services/immich/.env ]]; then
  ( cd services/immich && cp -n .env.example .env )
  echo ">> Set IMMICH_DB_PASSWORD in services/immich/.env"
fi
scripts/services/deploy_containers.sh

banner "Plex (native)"
if confirm "Install Plex now?"; then 
    scripts/services/install_plex.sh
    if [[ -f scripts/services/configure_plex_direct.sh ]]; then
        scripts/services/configure_plex_direct.sh
    fi
fi

banner "Jellyfin (native)"
if confirm "Install Jellyfin now?"; then 
    scripts/services/install_jellyfin.sh
    scripts/services/configure_jellyfin.sh
fi

banner "Launch at boot (launchd)"
scripts/automation/configure_launchd.sh

banner "Tailscale"
scripts/infrastructure/install_tailscale.sh
echo "Run: sudo tailscale up --accept-dns=true"

banner "HTTPS Configuration"
if confirm "Configure HTTPS serving with DNS fix?"; then
    scripts/infrastructure/configure_https.sh
fi

banner "Power Management"
if confirm "Configure Mac mini for 24/7 server operation (prevent sleep)?"; then
    scripts/infrastructure/configure_power.sh
fi

banner "Simple Landing Page"
if confirm "Enable simple landing page with direct service access?"; then
    scripts/services/enable_landing.sh
fi

echo "Done. Access via: https://$(tailscale status --json 2>/dev/null | grep '"DNSName"' | cut -d'"' -f4 | sed 's/\.$//' || echo 'your-device.your-tailnet.ts.net')"
