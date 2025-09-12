# Environment Variables Guide

This project uses environment variables to control **storage**, **services**, and **automation** behavior.
Export them in your shell or create a `.env.local` and `source` it before running scripts.

> Only set what you need — sensible defaults exist for most values.

---

## Storage (AppleRAID + Mounts)

| Variable | Default | Used by | Meaning / Effect |
|---------|---------|--------|------------------|
| `SSD_DISKS` | *(unset)* | `10_create_raid10_ssd.sh`, `09_rebuild_storage.sh` | Space-separated **disk identifiers** for the SSD array (e.g., `disk4 disk5` or `disk4 disk5 disk6 disk7`). **2 disks → mirror**, **4 disks → RAID10**. |
| `NVME_DISKS` | *(unset)* | `11_create_raid10_nvme.sh`, `09_rebuild_storage.sh` | Disk identifiers for the NVMe array. Same 2/4 logic. |
| `COLD_DISKS` | *(unset)* | `13_create_raid_coldstore.sh`, `09_rebuild_storage.sh` | Disk identifiers for the HDD archive array. |
| `SSD_RAID_NAME` | `warmstore` | storage scripts | AppleRAID set name (SSD). |
| `NVME_RAID_NAME` | `faststore` | storage scripts | AppleRAID set name (NVMe). |
| `COLD_RAID_NAME` | `coldstore` | storage scripts | AppleRAID set name (HDD). |
| `MEDIA_MOUNT` | `/Volumes/Media` | storage scripts | Mount point for `warmstore` (Plex/media). |
| `PHOTOS_MOUNT` | `/Volumes/Photos` | storage scripts | Mount point for `faststore` (Immich/photos). |
| `ARCHIVE_MOUNT` | `/Volumes/Archive` | storage scripts | Mount point for `coldstore` (HDD archive). |
| `RAID_I_UNDERSTAND_DATA_LOSS` | *(unset)* | `09_rebuild_storage.sh`, storage scripts | Must be `1` to allow **destructive rebuilds** (hard safety gate). |

**Behavior**: If a named AppleRAID set already exists, storage scripts **delete and recreate** it (re-runnable). Rebuilds are **destructive**; back up first.

---

## Immich

| Variable | Location | Meaning / Effect |
|---------|----------|------------------|
| `IMMICH_DB_PASSWORD` | `services/immich/.env` | Database password for Immich (Postgres). **Set this.** |
| `IMMICH_SERVER` | shell env (optional) | Used by the Takeout importer; e.g., `http://localhost:2283`. |
| `IMMICH_API_KEY` | shell env (optional) | API key for the importer (create in Immich → Account → API Keys). |

---

## Tailscale

| Variable | Default | Used by | Meaning |
|---------|---------|--------|--------|
| *(none required)* |  |  | Tailscale is interactive (`sudo tailscale up`). Pass flags directly (e.g., `--advertise-exit-node`). |

**Serve (optional):**
- `sudo tailscale serve --https=443   http://localhost:2283` → Immich over HTTPS on your tailnet name.  
- `sudo tailscale serve --https=32400 http://localhost:32400` → Plex over HTTPS.  
If you enable **landing page**, `./scripts/37_enable_simple_landing.sh` maps `:443` to the **landing page** instead.

---

## Reverse Proxy (Caddy)

| Variable | Default | Used by | Meaning |
|---------|---------|--------|--------|
| *(none required)* | | `37_enable_simple_landing.sh` | Enables landing page and configures Tailscale HTTPS serving. |

Routes:
- `/photos` → Immich (`localhost:2283`)
- `/plex` → Plex (`localhost:32400`)

---

## Updates & Launchd

- `./scripts/80_check_updates.sh [--apply]` runs manually; weekly job is configured via `./scripts/40_configure_launchd.sh`.
- No extra environment required.

---

## Backups (External HDD or NAS)

No variables required. Use explicit paths with:
```bash
# Backup warmstore to external drive
rsync -av --progress /Volumes/Media/ /Volumes/MyBackupDrive/MediaBackup/
# Restore: rsync -av /Volumes/MyBackupDrive/MediaBackup/ /Volumes/Media/
```

---

## Conventions Recap
- **Array names**: `faststore` (NVMe), `warmstore` (SSD), `coldstore` (HDD).  
- **Mounts**: `/Volumes/Photos`, `/Volumes/Media`, `/Volumes/Archive`.  
- **2 disks → mirror**, **4 disks → RAID10**.  
- Rebuilds require `RAID_I_UNDERSTAND_DATA_LOSS=1`.
