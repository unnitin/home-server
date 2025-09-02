#!/usr/bin/env bash
set -euo pipefail

echo "==> Mac Mini HomeServer bootstrap (safe mode)"
echo "This first run is non-destructive and will NOT touch disks."
echo

scripts/00_check_prereqs.sh
scripts/01_install_homebrew.sh
scripts/02_install_cli_tools.sh

echo
echo "Next steps:"
echo "  1) Identify disks:        scripts/03_disk_identification.sh"
echo "  2) (Optional) Create RAID: export RAID_I_UNDERSTAND_DATA_LOSS=1 && scripts/10_create_raid10_ssd.sh && scripts/11_create_raid10_nvme.sh && scripts/12_format_and_mount_raids.sh"
echo "  3) Install Docker/Colima: scripts/20_install_colima_docker.sh && scripts/21_start_colima.sh"
echo "  4) Deploy services (Immich): scripts/30_deploy_services.sh"
echo "  5) Install native Plex:      scripts/31_install_native_plex.sh
  6) Autostart on boot:        sudo scripts/40_configure_launchd.sh"
echo "  6) Tuning/hardening:      scripts/50_tune_power_network.sh && scripts/60_enable_ssh_firewall.sh"
