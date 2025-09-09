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
scripts/20_install_colima_docker.sh
scripts/21_start_colima.sh

banner "Immich"
if [[ ! -f services/immich/.env ]]; then
  ( cd services/immich && cp -n .env.example .env )
  echo ">> Set IMMICH_DB_PASSWORD in services/immich/.env"
fi
scripts/30_deploy_services.sh

banner "Plex (native)"
if confirm "Install Plex now?"; then scripts/31_install_native_plex.sh; fi

banner "Storage (DESTRUCTIVE)"
echo "Set SSD_DISKS/NVME_DISKS/COLD_DISKS and RAID_I_UNDERSTAND_DATA_LOSS=1 if you want to (re)build."
echo "Optional: set CLEAN_BEFORE_RAID=1 to wipe old AppleRAID sets & GPT on the target disks before creating."

read -r -p "Proceed to (re)build arrays now? [y/N] " a; case "$a" in
  [yY]* )
    # Optional pre-clean (DESTRUCTIVE)—only runs if CLEAN_BEFORE_RAID=1
    scripts/09_preclean_disks_for_raid.sh

    # If you want trace logs, run this setup with: DEBUG=1 ./setup/setup_full.sh
    if [[ "${DEBUG:-0}" == "1" ]]; then set -x; fi
    if ! {
      [[ -n "${SSD_DISKS:-}"  ]] && scripts/10_create_raid10_ssd.sh
      [[ -n "${NVME_DISKS:-}" ]] && scripts/11_create_raid10_nvme.sh
      [[ -n "${COLD_DISKS:-}" ]] && scripts/13_create_raid_coldstore.sh
      scripts/12_format_and_mount_raids.sh
    } 2>&1 | tee /tmp/homelab_storage.log ; then
      echo "❌ Storage step failed. See /tmp/homelab_storage.log for details."
      exit 1
    fi
    if [[ "${DEBUG:-0}" == "1" ]]; then set +x; fi
    ;;
  * )
    echo "Skipping destructive storage step."
    ;;
esac



banner "Launch at boot (launchd)"
sudo scripts/40_configure_launchd.sh

banner "Tailscale"
scripts/90_install_tailscale.sh
echo "Run: sudo tailscale up --accept-dns=true"

banner "Reverse proxy (optional)"
if confirm "Enable Caddy reverse proxy?"; then
  scripts/35_install_caddy.sh
  scripts/36_enable_reverse_proxy.sh
fi

echo "Done. Immich http://localhost:2283 | Plex http://localhost:32400/web"
