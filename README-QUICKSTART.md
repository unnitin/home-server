# Quick Start

> Prefer scripts under `setup/` for a guided experience.

## 0) Bootstrap (safe)
```bash
cd mac-mini-homeserver
setup/setup.sh
```

## 1) Storage (optional now; you can do this later)
> **Destructive when (re)building**. Backup first!

Example: **2 SSDs** for `warmstore` mirror today:
```bash
export SSD_DISKS="disk4 disk5"
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore
./scripts/12_format_and_mount_raids.sh
```

Later: **4 SSDs** (RAID10):
```bash
export SSD_DISKS="disk4 disk5 disk6 disk7"
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore
./scripts/12_format_and_mount_raids.sh
```

## 2) Docker runtime + Immich
```bash
./scripts/20_install_colima_docker.sh
./scripts/21_start_colima.sh
(cd services/immich && cp -n .env.example .env && ${EDITOR:-vi} .env)  # set IMMICH_DB_PASSWORD
./scripts/30_deploy_services.sh

# Immich web (local):
http://localhost:2283
```

## 3) Native Plex
```bash
./scripts/31_install_native_plex.sh
# Plex web (local):
http://localhost:32400/web
# In Plex settings, enable hardware transcoding if supported.
```

## 4) Autostart jobs (launchd)
```bash
sudo ./scripts/40_configure_launchd.sh
```

## 5) Remote access with Tailscale
```bash
./scripts/90_install_tailscale.sh
sudo tailscale up --accept-dns=true

# Direct HTTPS (best for mobile apps)
sudo tailscale serve --https=443   http://localhost:2283      # Immich
sudo tailscale serve --https=32400 http://localhost:32400      # Plex
# Immich app URL: https://<macmini>.<tailnet>.ts.net
# Plex app URL:   https://<macmini>.<tailnet>.ts.net:32400
```

## 6) Optional: single URL in browsers (reverse proxy)
```bash
./scripts/35_install_caddy.sh
./scripts/36_enable_reverse_proxy.sh
# Now inside your tailnet:
#   https://<macmini>.<tailnet>.ts.net        -> landing page
#   https://<macmini>.<tailnet>.ts.net/photos -> Immich
#   https://<macmini>.<tailnet>.ts.net/plex   -> Plex
```

## 7) Updates and diagnostics
```bash
# Check or apply updates
./scripts/80_check_updates.sh          # check
./scripts/80_check_updates.sh --apply  # apply

# Diagnostics examples
./diagnostics/check_raid_status.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_docker_services.sh
```

## Non-interactive setup (flags)
- Use `setup/setup_flags.sh` for no-prompt installs.  
- See `setup/MANPAGE-setup_flags.md` for full usage, flags, environment, and examples.
