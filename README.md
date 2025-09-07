# Mac Mini HomeServer (hakuna_mateti)

A batteries-included setup for a Mac mini home server with **Native Plex**, **Immich** (self‑hosted photos), secure **remote access via Tailscale**, and a clean, growable **storage layout** on macOS (AppleRAID).

## Features
- **Plex** (native app) with hardware transcoding.
- **Immich** (Docker via Colima) for multi-user photo backup & browsing.
- **Secure remote access** using Tailscale HTTPS; optional **Caddy reverse proxy** for a single browser URL.
- **Storage tiers** with growth path:
  - `faststore` (NVMe): 2-disk **mirror** or 4-disk **RAID10**.
  - `warmstore` (SSD): 2-disk **mirror** now, later 4-disk **RAID10**.
  - `coldstore` (HDD): future archive tier; optional single external HDD works too.
- **Re-runnable storage scripts**: tear down existing AppleRAID sets and rebuild (with a hard safety gate).
- **Diagnostics** and **weekly update checks**.
- **Google Takeout → Immich** helper.

## Repository layout
```
/                       # docs and entry points
├─ README.md
├─ README-QUICKSTART.md
├─ ENVIRONMENT.md
├─ setup/               # setup entrypoints
│  ├─ setup.sh          # safe bootstrap (brew + CLI)
│  ├─ setup_full.sh     # interactive full setup
│  ├─ setup_flags.sh    # non-interactive flags
│  └─ MANPAGE-setup_flags.md
├─ scripts/             # RAID, tailscale, updates, helpers, etc.
├─ services/            # immich, caddy (reverse proxy), etc.
├─ launchd/             # autostart plists
└─ diagnostics/         # health checks and logs helpers
```

## Setup options
Pick **one** of these entrypoints in `setup/`:

- `setup.sh` → **safe bootstrap only** (Homebrew + CLI tools).  
- `setup_full.sh` → **interactive full** install with confirmations (Plex, Immich, optional rebuild, Tailscale, proxy).  
- `setup_flags.sh` → **non-interactive**; run selected steps via flags. See `setup/MANPAGE-setup_flags.md`.

> For a fast start, read **README-QUICKSTART.md**.

## Storage model
- `faststore` (NVMe) → `/Volumes/Photos` (Immich/originals)
- `warmstore` (SSD) → `/Volumes/Media` (Plex media)
- `coldstore` (HDD/archive) → `/Volumes/Archive` (optional)

**2 disks → mirror**, **4 disks → RAID10**. Rebuilds are **destructive** (backup → rebuild → restore). Scripts are **re-runnable** and delete any existing AppleRAID set with the same name.

### Grow path example (2 → 4 SSDs for warmstore)
1) Back up `/Volumes/Media` to external HDD (or to faststore/coldstore).  
2) Rebuild with 4 disks.  
3) Restore data back to `/Volumes/Media`.

## Remote access
- **Tailscale** gives you an encrypted VPN overlay and HTTPS:  
  - Immich: `sudo tailscale serve --https=443   http://localhost:2283`  
  - Plex:   `sudo tailscale serve --https=32400 http://localhost:32400`  
- **Optional reverse proxy (Caddy)** provides a single browser origin:  
  - `https://<macmini>.<tailnet>.ts.net/photos` → Immich  
  - `https://<macmini>.<tailnet>.ts.net/plex` → Plex  
  - A small landing page (“hakuna_mateti HomeServer”) with health dots is included.

## Backups (simple external HDD)
You can use any mounted folder (no RAID needed). Helpers (optional):
- `scripts/14_backup_store.sh warmstore /Volumes/MyBackupDrive/MediaBackup`
- `scripts/15_restore_store.sh /Volumes/MyBackupDrive/MediaBackup warmstore`

Both use `rsync` and are **non-destructive** by default.

## Diagnostics & updates
- Diagnostics scripts in `diagnostics/` (e.g., RAID health, Plex process, Docker services).
- Weekly update checks via launchd; run on demand with `scripts/80_check_updates.sh [--apply]`.

## Environment variables
See **ENVIRONMENT.md** for all variables, defaults, and what they control.

## Notes
- Tested on Apple Silicon macOS with Homebrew in `/opt/homebrew`.
- AppleRAID lacks online expansion; you’ll rebuild to change level/width → use the provided backup/restore flow.
- You can keep using **Tailscale direct ports** for mobile apps even if you enable the reverse proxy.

## Repository tree

```
mac-mini-homeserver/
├─ README.md
├─ README-QUICKSTART.md
├─ ENVIRONMENT.md
├─ setup/
│  ├─ setup.sh
│  ├─ setup_full.sh
│  ├─ setup_flags.sh
│  └─ MANPAGE-setup_flags.md
├─ scripts/
│  ├─ 09_rebuild_storage.sh
│  ├─ 10_create_raid10_ssd.sh
│  ├─ 11_create_raid10_nvme.sh
│  ├─ 12_format_and_mount_raids.sh
│  ├─ 13_create_raid_coldstore.sh
│  ├─ 14_backup_store.sh
│  ├─ 15_restore_store.sh
│  ├─ 20_install_colima_docker.sh
│  ├─ 21_start_colima.sh
│  ├─ 30_deploy_services.sh
│  ├─ 31_install_native_plex.sh
│  ├─ 35_install_caddy.sh
│  ├─ 36_enable_reverse_proxy.sh
│  ├─ 37_disable_reverse_proxy.sh
│  ├─ 40_configure_launchd.sh
│  ├─ 50_tune_power_network.sh
│  ├─ 60_enable_ssh_firewall.sh
│  ├─ 70_takeout_to_immich.sh
│  ├─ 80_check_updates.sh
│  ├─ 90_install_tailscale.sh
│  └─ _raid_common.sh
├─ services/
│  ├─ immich/
│  │  ├─ docker-compose.yml
│  │  └─ .env.example
│  └─ caddy/
│     ├─ Caddyfile
│     └─ site/index.html
├─ launchd/
│  ├─ io.homelab.colima.plist
│  ├─ io.homelab.compose.immich.plist
│  ├─ io.homelab.updatecheck.plist
│  └─ io.homelab.tailscale.plist
└─ diagnostics/
   ├─ README.md
   ├─ check_raid_status.sh
   ├─ check_plex_native.sh
   ├─ check_docker_services.sh
   ├─ collect_logs.sh
   ├─ network_port_check.sh
   └─ verify_media_paths.sh
```

## Tools just added

- Google Takeout → Immich helper: `scripts/70_takeout_to_immich.sh /path/to/Takeout.zip`  
  Optional env: `IMMICH_SERVER`, `IMMICH_API_KEY` (for `immich-go` CLI).

- Diagnostics (see `diagnostics/`):
  - `check_raid_status.sh`
  - `check_plex_native.sh`
  - `check_docker_services.sh`
  - `network_port_check.sh <host> <port>`
  - `collect_logs.sh`
  - `verify_media_paths.sh`

## New additions

### Google Takeout → Immich helper
Use `scripts/70_takeout_to_immich.sh` to import your Google Photos Takeout export.

```bash
scripts/70_takeout_to_immich.sh ~/Downloads/takeout-photos.zip
```

- Extracts and stages media files for upload.  
- If you install [`immich-go`](https://github.com/immich-app/immich-go) and set env vars, it will auto-upload:
  - `IMMICH_SERVER=http://localhost:2283`
  - `IMMICH_API_KEY=<your-api-key>`

### Diagnostics suite
See [`diagnostics/README.md`](diagnostics/README.md) for full details.

- RAID, Plex, Docker, ports, logs, and storage checks.  
- Run them individually as needed.

Example:
```bash
diagnostics/check_raid_status.sh
diagnostics/check_plex_native.sh
```
