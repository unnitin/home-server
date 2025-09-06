
# Environment Variables

## Storage
- `SSD_DISKS`, `NVME_DISKS`, `COLD_DISKS` — space-separated disk IDs (e.g., `disk4 disk5` or `disk4 disk5 disk6 disk7`)
- `SSD_RAID_NAME=warmstore`, `NVME_RAID_NAME=faststore`, `COLD_RAID_NAME=coldstore`
- Mounts: `MEDIA_MOUNT=/Volumes/Media`, `PHOTOS_MOUNT=/Volumes/Photos`, `ARCHIVE_MOUNT=/Volumes/Archive`
- `RAID_I_UNDERSTAND_DATA_LOSS=1` — required for any rebuild

**2 disks → mirror**, **4 disks → RAID10** (two mirrors striped).

## Immich
- `IMMICH_DB_PASSWORD` in `services/immich/.env`

## Tailscale / Reverse proxy
None required; see scripts.
