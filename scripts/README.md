# Scripts

This folder contains all automation scripts for the Mac Mini HomeServer.

## Setup Flow

Run scripts in order, or use the top-level `./setup.sh` wrapper.

1. `00_check_prereqs.sh` → verify macOS environment
2. `01_install_homebrew.sh` → install Homebrew package manager
3. `02_install_cli_tools.sh` → install CLI tools (jq, yq, coreutils, docker, colima, etc.)
4. `03_disk_identification.sh` → list external disks to identify which are SSD vs NVMe
5. `10_create_raid10_ssd.sh` / `11_create_raid10_nvme.sh` → create RAID10 arrays (⚠️ destructive)
6. `12_format_and_mount_raids.sh` → format/mount arrays, create folders for Plex/Immich
7. `20_install_colima_docker.sh` → install Colima + Docker
8. `21_start_colima.sh` → start Colima VM
9. `30_deploy_services.sh` → deploy Immich service via Docker
10. `31_install_native_plex.sh` → install Plex Media Server natively (HW transcoding)
11. `40_configure_launchd.sh` → install and load launchd plists (Colima + Immich + update check)
12. `50_tune_power_network.sh` → disable sleep, enable WOL
13. `60_enable_ssh_firewall.sh` → enable SSH + firewall
14. `70_takeout_to_immich.sh` → helper for Google Photos Takeout migration
15. `80_check_updates.sh` → weekly update checker (brew + docker); run with `--apply` to upgrade

## Usage

Run each script as:

```bash
./scripts/<script>.sh
```

Many scripts require `sudo` (disk, launchd, firewall).
