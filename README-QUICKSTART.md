
# Quick Start

```bash
# 0) Bootstrap
setup/setup.sh

# 1) (Optional now) create arrays
export SSD_DISKS="disk4 disk5"        # 2 disks → mirror
export RAID_I_UNDERSTAND_DATA_LOSS=1  # REQUIRED for destructive rebuilds
scripts/10_create_raid10_ssd.sh
scripts/12_format_and_mount_raids.sh

# 2) Docker + Immich
scripts/20_install_colima_docker.sh
scripts/21_start_colima.sh
(cd services/immich && cp -n .env.example .env && $EDITOR .env)
scripts/30_deploy_services.sh

# 3) Native Plex
scripts/31_install_native_plex.sh

# 4) Launch at boot
sudo scripts/40_configure_launchd.sh

# 5) Tailscale + HTTPS
scripts/90_install_tailscale.sh
sudo tailscale up --accept-dns=true
sudo tailscale serve --https=443   http://localhost:2283
sudo tailscale serve --https=32400 http://localhost:32400

# Optional: reverse proxy (one origin)
scripts/35_install_caddy.sh
scripts/36_enable_reverse_proxy.sh
```
