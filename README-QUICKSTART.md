# Quick Start (Mac Mini HomeServer)

A minimal, copy‑paste guide to bring up the server with **native Plex** and **Immich**.

> ⚠️ RAID creation is **destructive**. Skip RAID if you’re just testing.

---

## 0) Clone & enter
```bash
git clone https://github.com/you/mac-mini-homeserver.git
cd mac-mini-homeserver
```

## 1) Bootstrap (safe)
```bash
./setup.sh
```

## 2) (Optional) Create RAID‑10 arrays (4×SSD, 4×NVMe)
```bash
scripts/03_disk_identification.sh                 # find disk IDs (disk4 disk5 ...)
export SSD_DISKS="disk4 disk5 disk6 disk7"
export NVME_DISKS="disk8 disk9 disk10 disk11"
export RAID_I_UNDERSTAND_DATA_LOSS=1              # REQUIRED for destructive ops
./scripts/10_create_raid10_ssd.sh
./scripts/11_create_raid10_nvme.sh
./scripts/12_format_and_mount_raids.sh            # mounts to /Volumes/Media and /Volumes/Photos
```

## 3) Start Docker runtime (for Immich)
```bash
scripts/20_install_colima_docker.sh
scripts/21_start_colima.sh
```

## 4) Bring up Immich
```bash
( cd services/immich && cp .env.example .env )    # set IMMICH_DB_PASSWORD in .env
scripts/30_deploy_services.sh
# Web UI: http://localhost:2283 (first signup becomes admin)
```

## 5) Install Plex natively (hardware transcoding)
```bash
scripts/31_install_native_plex.sh
# Web UI: http://localhost:32400/web
# In Settings → Transcoder → enable "Use hardware acceleration" (Plex Pass)
# Point libraries to /Volumes/Media/{Movies,TV,Music}
```

## 6) Autostart jobs (boot persistence)
```bash
sudo scripts/40_configure_launchd.sh
# Starts Colima at boot, ensures Immich is up, and runs weekly update checks (Sun 03:30)
```

## 7) Migration helper (Google Photos → Immich)
```bash
export IMMICH_SERVER="http://localhost:2283"
export IMMICH_API_KEY="YOUR_KEY"                  # create in Immich → Account → API Keys
./scripts/70_takeout_to_immich.sh -i /path/to/TakeoutZips -w /tmp/immich-import
```

## 8) Updates (manual)
```bash
./scripts/80_check_updates.sh          # check only
./scripts/80_check_updates.sh --apply  # apply brew + cask + docker updates
```

---

## Verify
```bash
# Immich
docker ps | grep -E 'immich|redis|postgres'
open http://localhost:2283

# Plex (native)
pgrep -fl "Plex Media Server" || echo "Plex not running"
open http://localhost:32400/web
```

## Troubleshooting
See `diagnostics/README.md` and run:
```bash
./diagnostics/check_raid_status.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_docker_services.sh
./diagnostics/network_port_check.sh
```


---

## Remote Access with Tailscale

```bash
scripts/90_install_tailscale.sh
sudo tailscale up --accept-dns=true
sudo tailscale serve --https=443 http://localhost:2283   # proxy Immich with HTTPS
```

On your phone:
- Install **Tailscale** and **Immich** apps.  
- Sign into Tailscale (same account as Mac mini).  
- In Immich app, set server URL to:  
  ```
  https://<macmini-name>.<tailnet>.ts.net
  ```

Now you can browse and back up photos from anywhere, securely.



### Plex via Tailscale

Plex is also proxied with HTTPS through Tailscale Serve:

```bash
sudo tailscale serve --https=32400 http://localhost:32400
```

Access Plex from anywhere at:

```
https://<macmini-name>.<tailnet>.ts.net
```



### (Optional) Proxy Plex over HTTPS too
```bash
sudo tailscale serve --https=32400 http://localhost:32400
# Plex URL (inside tailnet):
# https://<macmini-name>.<tailnet>.ts.net:32400
```


---

## Unified Access with Reverse Proxy (Optional)

```bash
./scripts/95_setup_caddy_proxy.sh
```

After this, use:
- Immich → https://<macmini>.<tailnet>.ts.net/photos
- Plex   → https://<macmini>.<tailnet>.ts.net/plex
- Landing → https://<macmini>.<tailnet>.ts.net/


### Optional: one URL for browsers (reverse proxy)
```bash
./scripts/35_install_caddy.sh
./scripts/36_enable_reverse_proxy.sh
# Then:
#   Immich: https://<macmini>.<tailnet>.ts.net/photos
#   Plex:   https://<macmini>.<tailnet>.ts.net/plex
```
To disable:
```bash
./scripts/37_disable_reverse_proxy.sh
```


### Rebuild / Grow storage later (2 → 4 disks)
```bash
# Example: warmstore today with 2 SSDs (mirror), expand later to 4 (RAID10)
export SSD_DISKS="disk4 disk5"                      # today
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore

# Later (after backing up data), recreate with 4 disks:
export SSD_DISKS="disk4 disk5 disk6 disk7"
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore
```
> Rebuilds are destructive. Backup → Rebuild → Restore.


### Simple external HDD backup (no RAID)
```bash
# Backup Media to a folder on your external drive
./scripts/14_backup_store.sh warmstore /Volumes/MyBackupDrive/MediaBackup

# Restore after rebuild
./scripts/15_restore_store.sh /Volumes/MyBackupDrive/MediaBackup warmstore
```
