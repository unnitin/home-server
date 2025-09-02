# Quick Start Guide

This guide gives you the **minimal commands** to get your Mac Mini HomeServer running.

For full details, see `README.md`.

---

## 1. Clone the repo
```bash
git clone https://github.com/you/mac-mini-homeserver.git
cd mac-mini-homeserver
```

## 2. Run bootstrap (safe, non-destructive)
```bash
./setup.sh
```

This installs Homebrew and CLI tools. **No disks are touched yet.**

---

## 3. Identify your disks (4× SSD + 4× NVMe)
```bash
./scripts/03_disk_identification.sh
```

Set environment variables:
```bash
export SSD_DISKS="disk4 disk5 disk6 disk7"
export NVME_DISKS="disk8 disk9 disk10 disk11"
```

---

## 4. Create RAID10 arrays (⚠️ destructive)
```bash
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/10_create_raid10_ssd.sh
./scripts/11_create_raid10_nvme.sh
./scripts/12_format_and_mount_raids.sh
```

---

## 5. Install services
- **Docker/Colima for Immich:**
```bash
./scripts/20_install_colima_docker.sh
./scripts/21_start_colima.sh
./scripts/30_deploy_services.sh
```

- **Native Plex:**
```bash
./scripts/31_install_native_plex.sh
```

---

## 6. Enable auto-start + tuning
```bash
sudo ./scripts/40_configure_launchd.sh
./scripts/50_tune_power_network.sh
./scripts/60_enable_ssh_firewall.sh
```

---

## 7. Access your services
- **Plex (native):** http://<mac-mini-ip>:32400/web  
- **Immich (photos):** http://<mac-mini-ip>:2283

---

## 8. Diagnostics
Check health if something seems off:
```bash
./diagnostics/check_raid_status.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_docker_services.sh
```

---

## 9. Google Photos import (optional)
```bash
export IMMICH_SERVER="http://localhost:2283"
export IMMICH_API_KEY="YOUR_KEY"
./scripts/70_takeout_to_immich.sh -i /path/to/TakeoutZips -w /tmp/immich-import
```

---

## 10. Updates
- Weekly job runs automatically.  
- Run manually:
```bash
./scripts/80_check_updates.sh         # check only
./scripts/80_check_updates.sh --apply # apply updates
```
