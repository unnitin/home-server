#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

banner(){ echo; echo "=== $* ==="; }
confirm(){ read -r -p "$1 [y/N] " a || true; [[ "${a,,}" =~ ^y(es)?$ ]]; }

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
if confirm "Proceed to (re)build arrays now?"; then
  [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" == "1" ]] || { echo "Set RAID_I_UNDERSTAND_DATA_LOSS=1"; exit 2; }
  [[ -n "${SSD_DISKS:-}"  ]] && scripts/10_create_raid10_ssd.sh
  [[ -n "${NVME_DISKS:-}" ]] && scripts/11_create_raid10_nvme.sh
  [[ -n "${COLD_DISKS:-}" ]] && scripts/13_create_raid_coldstore.sh
  scripts/12_format_and_mount_raids.sh || true
fi

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
