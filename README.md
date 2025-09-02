# Mac Mini HomeServer

Turn a Mac mini (Apple Silicon or Intel) into an always-on home server with:

- **RAID 10** on macOS for _two independent arrays_: `4× SSD` and `4× NVMe` (AppleRAID + APFS).
- **Plex Media Server** for streaming.
- **Immich** for multi-user photo backup & management.
- **Auto-start on boot** and self-healing restarts via `launchd` + Docker restart policies.
- Sensible **homeserver hardening & tuning** (power/sleep, SSH, firewall, health checks).
- A **diagnostics module** with scripts to debug common issues.

> ⚠️ **Data loss warning**: RAID setup will ERASE the specified disks. The scripts default to a DRY RUN. You must explicitly opt-in to destructive actions.

---

## Quick Start (safe, non-destructive)

```bash
git clone https://github.com/you/mac-mini-homeserver.git
cd mac-mini-homeserver
./setup.sh
```

- The first run is **dry-run**: it installs tooling and shows what would happen.
- When you're ready to actually create RAID arrays, set the env var and re-run specific scripts (see below).

---

## Requirements

- macOS 12+ (Monterey) through current.
- 8 external drives: **4 SSDs** and **4 NVMe** (Thunderbolt/USB enclosures). They will be grouped into **two RAID‑10 arrays**:
  - `warmstore` ← 4× SSD (as two mirrors striped together)
  - `faststore` ← 4× NVMe (as two mirrors striped together)
- Admin user with `sudo`.
- Internet connection (Homebrew & Docker/Colima).

---

## What gets installed

- **Homebrew** + CLI tools (`git`, `jq`, `yq`, `smartmontools`, `coreutils`).
- **Colima** + **Docker** CLI for running services without GUI.
- **Plex (native macOS app)** – installed via Homebrew Cask with hardware-accelerated transcoding; media at `/Volumes/Media`.
- **Immich** (Docker) – config/data at `services/immich`, originals at `/Volumes/Photos/originals`.
- **launchd** jobs so that services start automatically after boot.

---

## Disks & RAID 10 (AppleRAID + APFS)

We create **two** independent RAID‑10 arrays by first making **mirrors (RAID‑1)** and then **striping (RAID‑0)** across those mirrors:

- SSD: `(s1 ↔ s2)` + `(s3 ↔ s4)` ⇒ stripe ⇒ `warmstore`
- NVMe: `(n1 ↔ n2)` + `(n3 ↔ n4)` ⇒ stripe ⇒ `faststore`

> AppleRAID supports building mirrored sets and then combining them into a striped set; the resulting virtual disk is then formatted as **APFS** and mounted. See `scripts/10_create_raid10_ssd.sh` for details.

### Identify your disks

Run:

```bash
./scripts/03_disk_identification.sh
```

Then export the four disk identifiers for each array as environment variables (`/dev/diskX`, not partitions like `diskXs1`). Example:

```bash
export SSD_DISKS="disk4 disk5 disk6 disk7"
export NVME_DISKS="disk8 disk9 disk10 disk11"
```

> The scripts **verify** you passed **exactly four** unique disk identifiers each.

### Create RAID 10 arrays (DESTRUCTIVE)

```bash
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/10_create_raid10_ssd.sh
./scripts/11_create_raid10_nvme.sh
./scripts/12_format_and_mount_raids.sh
```

This will create and mount:

- `/Volumes/Media` (from `warmstore`) for Plex libraries
- `/Volumes/Photos` (from `faststore`) for Immich originals/library

---

## Services (Plex + Immich)

### Install container runtime (for Immich) & bring it up

```bash
./scripts/20_install_colima_docker.sh
./scripts/21_start_colima.sh
./scripts/30_deploy_services.sh
```

- **Plex (native) UI**: http://localhost:32400/web (or your Mac mini’s LAN IP)
- **Immich UI**: http://localhost:2283 (first admin user based on `.env` in `services/immich/.env`)

> Note: Hardware transcoding for Plex from a Docker container on macOS is limited/unsupported. If you need **VideoToolbox hardware acceleration**, consider installing Plex natively via the macOS installer instead. See `README-native-plex.md` for notes.


### Install Plex natively (recommended on macOS for HW transcoding)

```bash
./scripts/31_install_native_plex.sh
```

### Autostart on boot

```bash
sudo ./scripts/40_configure_launchd.sh
```

This installs LaunchDaemons to:

- Start **Colima** on boot
- Ensure `docker compose up -d` runs for Plex and Immich
- Keep services alive with restart policies

---

## Hardening & Tuning

```bash
./scripts/50_tune_power_network.sh
./scripts/60_enable_ssh_firewall.sh
```

- Prevent sleep and enable wake-on-LAN
- Turn on the macOS application firewall
- Enable SSH for remote admin

---

## Diagnostics

See the **`diagnostics/`** folder and its README for common checks:

- RAID status & rebuild helpers
- Docker/Compose health & logs
- Port and network checks
- Media path verifier for Plex

---

## Configuration

Copy the sample env file and adjust ports/paths/users/passwords:

```bash
cp env.example .env
( cd services/plex && cp .env.example .env )
( cd services/immich && cp .env.example .env )
```

---

## Uninstall

- Stop launchd jobs: `sudo launchctl unload /Library/LaunchDaemons/io.homelab.*.plist`
- `docker compose down` in each `services/*` dir
- Destroy arrays **(this is destructive)** using `diskutil appleRAID delete <UUID>`

---

## Notes & Caveats

- AppleRAID compound sets (mirrors + stripes) are supported; the created virtual disk is then formatted as APFS.
- Docker on macOS runs in a lightweight VM (Colima). Paths under `/Volumes/*` are bind-mounted into containers.
- Plex hardware transcoding via Docker on macOS is limited; consider native Plex if you need it.

---

## Contributing

PRs welcome!

## Google Photos → Immich (helper)

Use the helper to unzip Google Takeout archives, normalize folders, build album views, and bulk upload to Immich (via `immich-go`).

```bash
export IMMICH_SERVER="http://localhost:2283"
export IMMICH_API_KEY="YOUR_KEY"     # Create in Immich → Account → API Keys
./scripts/70_takeout_to_immich.sh -i /path/to/TakeoutZips -w /tmp/immich-import
```

- If you already extracted the Takeout, add `--no-unzip` and point `-i` to the extracted folder.
- The script searches for `Google Photos` roots automatically, collects media into a unified tree, and creates an `albums/` symlink tree to mirror Google albums.
- Uploads using **immich-go** (binary or Docker). If not installed, the script prints instructions and leaves everything staged for manual upload.



## Scheduled update checks

A weekly **update check** job runs via `launchd` every **Sunday at 03:30** and logs to `/var/log/homeserver-updatecheck.*.log`.
It checks:
- Homebrew formulae and casks (including **Plex Media Server**)
- Docker images for Immich stack (pulls latest tags)

Enable the job (installed with other LaunchDaemons):
```bash
sudo scripts/40_configure_launchd.sh
```

Run a manual check or apply updates immediately:
```bash
# Check only (safe):
./scripts/80_check_updates.sh

# Apply upgrades (brew upgrade, brew cask upgrade --greedy, docker compose up -d for Immich):
./scripts/80_check_updates.sh --apply
```


## Remote Access with Tailscale (HTTPS)

Tailscale lets you securely reach your Mac mini from anywhere without port forwarding.

### Setup on the Mac mini

```bash
./scripts/90_install_tailscale.sh
# Then sign in interactively (Google/Microsoft/etc):
sudo tailscale up --accept-dns=true
# Enable HTTPS proxy for Immich (port 2283):
sudo tailscale serve --https=443 http://localhost:2283
```

Now Immich is reachable at:

```
https://<macmini-name>.<tailnet>.ts.net
```

### Setup on your phone

1. Install **Tailscale** app from iOS App Store or Google Play.  
2. Sign in with the same account used on the Mac mini.  
3. Confirm it shows **Connected** (VPN key icon appears).  
4. Install **Immich** mobile app.  
   - When asked for server URL, enter:  
     ```
     https://<macmini-name>.<tailnet>.ts.net
     ```
5. Sign in with your Immich account (created earlier in the web UI).  

Now backups and browsing work the same at home or while traveling.

### Notes

- **MagicDNS**: makes `<macmini-name>.tailnet.ts.net` resolve automatically, no IPs needed.  
- **HTTPS**: served via Tailscale with automatic certificates trusted by all your Tailscale devices.  
- **Plex**: proxied by default, e.g.  
  ```bash
  sudo tailscale serve --https=32400 http://localhost:32400
  ```
  Then use `https://<macmini-name>.<tailnet>.ts.net:32400` for Plex.  



## Unified Access with Reverse Proxy (Optional)

If you want a cleaner browser experience without ports, enable the bundled **Caddy reverse proxy**:

```bash
./scripts/95_setup_caddy_proxy.sh
```

This installs Caddy, sets up the provided `Caddyfile`, and configures Tailscale to route HTTPS (443) into Caddy.

You then get:

- Immich → `https://<macmini>.<tailnet>.ts.net/photos`
- Plex   → `https://<macmini>.<tailnet>.ts.net/plex`
- Landing page → `https://<macmini>.<tailnet>.ts.net/`

### Notes

- **Browser UX**: one domain, no ports.  
- **Apps**: Immich and Plex apps still prefer their direct URLs (`/` and `:32400`).  
- **Fallback**: If you stop Caddy, direct Tailscale Serve URLs still work.  
- **Remove**:  
  ```bash
  sudo brew services stop caddy
  sudo tailscale serve --reset
  ```


## Optional: Unified HTTPS with Reverse Proxy (Caddy)

If you prefer **one HTTPS origin** for browsers (no ports), enable the bundled reverse proxy:

```bash
./scripts/35_install_caddy.sh              # installs Caddy and loads Caddyfile (localhost:8443)
./scripts/36_enable_reverse_proxy.sh       # Tailscale HTTPS:443 -> Caddy -> /photos,/plex
```

Browse inside your tailnet:
- Immich (web): `https://<macmini>.<tailnet>.ts.net/photos`
- Plex (web):   `https://<macmini>.<tailnet>.ts.net/plex`

> **Mobile apps:** keep standard base URLs (Immich at root, Plex on :32400). This proxy primarily improves browser UX.

To undo:
```bash
./scripts/37_disable_reverse_proxy.sh
```


## Re-runnable Storage (Teardown & Rebuild)

The storage scripts are **idempotent** and can be re-run. If an AppleRAID set with the target name already exists,
the scripts will delete it and recreate from the provided disk list.

> ⚠️ **Data loss warning:** Rebuilds **erase** the target array. Always back up first (e.g., to `coldstore` or external).

### 2 or 4 disks

- Provide **2 disks** → a **RAID1 mirror** is created.
- Provide **4 disks** → two mirrors are created and **striped** (RAID10).

### Rebuild examples

```bash
# Rebuild SSD (warmstore) as 2-disk mirror (today), or 4-disk RAID10 (later)
export SSD_DISKS="disk4 disk5"                 # or: "disk4 disk5 disk6 disk7"
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh warmstore

# Rebuild NVMe (faststore)
export NVME_DISKS="disk8 disk9 disk10 disk11"  # or 2-disk mirror initially
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh faststore
```

### Coldstore (future)

```bash
export COLD_DISKS="disk12 disk13"      # or 4 disks for RAID10
export RAID_I_UNDERSTAND_DATA_LOSS=1
./scripts/09_rebuild_storage.sh coldstore
```

The rebuild script temporarily **stops Immich** and tries to stop **Plex**, then recreates the arrays and **restarts services**.


## Using a Single External HDD for Cold Storage (No RAID)

You can back up and restore without creating a RAID array. Any **mounted directory** works:
- External USB HDD (e.g., `/Volumes/MyBackupDrive`)
- NAS share mounted under `/Volumes/...`

### Backup (to external HDD)
```bash
# Media (warmstore) -> external
./scripts/14_backup_store.sh warmstore /Volumes/MyBackupDrive/MediaBackup

# Photos (faststore) -> external
./scripts/14_backup_store.sh faststore  /Volumes/MyBackupDrive/PhotosBackup
```

### Restore (after rebuild)
```bash
# External -> Media (warmstore)
./scripts/15_restore_store.sh /Volumes/MyBackupDrive/MediaBackup warmstore

# External -> Photos (faststore)
./scripts/15_restore_store.sh /Volumes/MyBackupDrive/PhotosBackup faststore
```

**Notes**
- These scripts are **non-destructive** by default; they do **NOT** delete files on the destination unless you add `--delete-after` inside the scripts.
- Filesystems: APFS is ideal on macOS; use exFAT if you need cross-platform compatibility (no reformat needed if the disk already has data).
- To avoid Spotlight overhead on backup disks, you can exclude the drive in **System Settings → Siri & Spotlight → Spotlight Privacy**.
