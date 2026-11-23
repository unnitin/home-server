#!/usr/bin/env bash
# Make the golden VM look like the real mini at the storage and service level.
# Runs INSIDE the VM, once, while vm.sh builds the golden image. Every clone
# made for a rehearsal starts from this state.
#
#   DATA_DISK_BYTES=<size of the blank data disk> provision_golden.sh
#
# What it sets up, mirroring what was observed on the mini on 2026-11-23:
#   - Homebrew python3.11 with the MCP server's packages (the plist's path)
#   - faststore: an APFS volume on one blank data disk, with the same folder
#     layout and permissions as the real one, plus small fixture files (no
#     real data). Not an AppleRAID mirror like the mini's: a mirror inside a
#     macOS VM deadlocks on its first flush under write load (reproduced
#     2026-11-23), so RAID diagnostics can't be rehearsed here.
#   - Plex and Jellyfin data folders symlinked into faststore, as on the mini
#   - a root-owned, unreadable /Volumes/warmstore folder and no warmstore
#     volume (D21). macOS removes the empty folder at the next boot; the jobs
#     fail the same way without it.
#   - sudo that needs a password, so boot jobs behave as they do on the mini
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh"

DATA_DISK_BYTES="${DATA_DISK_BYTES:?set DATA_DISK_BYTES to the data disk size}"
VM_PASSWORD="${VM_PASSWORD:-admin}"
FS=/Volumes/faststore

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }
as_root()   { printf '%s\n' "$VM_PASSWORD" | sudo -S -p '' "$@"; }

disk_field() {
    diskutil info -plist "$1" 2>/dev/null | plutil -extract "$2" raw - 2>/dev/null || true
}

# Whole disks of exactly DATA_DISK_BYTES with no partition scheme.
blank_data_disks() {
    local d
    for d in $(diskutil list | awk '/^\/dev\/disk[0-9]+ / {sub("/dev/", "", $1); print $1}'); do
        [[ "$(disk_field "$d" TotalSize)" == "$DATA_DISK_BYTES" ]] || continue
        [[ -z "$(disk_field "$d" Content)" ]] || continue
        echo "$d"
    done
}

log_info "Python 3.11 and MCP server packages"
if [[ ! -x /opt/homebrew/bin/python3.11 ]]; then
    brew install --quiet python@3.11
fi
/opt/homebrew/bin/python3.11 -m pip install --quiet --break-system-packages \
    'mcp>=1.27,<2' uvicorn starlette

if [[ ! -d "$FS" ]]; then
    read -r -a disks <<<"$(blank_data_disks | tr '\n' ' ')"
    if [[ ${#disks[@]} -ne 1 ]]; then
        log_error "expected 1 blank ${DATA_DISK_BYTES}-byte data disk, found ${#disks[@]}"
        diskutil list >&2
        exit 1
    fi
    log_info "Creating faststore on ${disks[0]} (virtual disk)"
    as_root diskutil eraseDisk APFS faststore GPT "${disks[0]}"
fi
for _ in $(seq 1 30); do [[ -d "$FS" ]] && break; sleep 1; done
[[ -d "$FS" ]] || { log_error "$FS did not mount"; exit 1; }
bash "$HERE/io_smoke.sh" "$FS"

log_info "faststore layout and fixtures (no real data)"
as_root chown "$(id -un):staff" "$FS"
mkdir -p "$FS"/immich/{library,profile,thumbs,encoded-video,backups,database} \
    "$FS"/immich/upload/00000000-0000-4000-8000-000000000001/2024/06 \
    "$FS"/plex/{metadata,cache,logs,transcoding,processing} \
    "$FS"/jellyfin/{config,cache,logs,transcoding}
chmod 700 "$FS/immich/database"
echo 16 >"$FS/immich/database/PG_VERSION"
for i in 1 2 3; do
    printf 'fixture photo %s\n' "$i" \
        >"$FS/immich/upload/00000000-0000-4000-8000-000000000001/2024/06/IMG_000$i.jpg"
done
echo "-- fixture dump complete" | gzip \
    >"$FS/immich/backups/immich-db-backup-20260101T020000-v2.1.0-pg16.10.sql.gz"
echo fixture >"$FS/immich/backups/.immich"

log_info "Plex and Jellyfin data folders live on faststore, as on the mini"
APPSUP="$HOME/Library/Application Support"
mkdir -p "$APPSUP"
ln -sfn "$FS/plex/metadata" "$APPSUP/Plex Media Server"
ln -sfn "$FS/jellyfin/config" "$APPSUP/jellyfin"

log_info "warmstore: unreadable root-owned folder, no volume (D21)"
as_root mkdir -p /Volumes/warmstore
as_root chown root:wheel /Volumes/warmstore
as_root chmod 111 /Volumes/warmstore

log_info "Power settings as on the mini: never sleep, display sleep 1"
as_root pmset -a sleep 0 displaysleep 1 disksleep 0 >/dev/null

log_info "sudo needs a password, as on the mini"
for f in /etc/sudoers.d/*; do
    [[ -f "$f" ]] || continue
    if as_root grep -q NOPASSWD "$f"; then
        as_root mv "$f" "/var/root/$(basename "$f").disabled"
        log_info "  disabled $f"
    fi
done
sudo -k
if sudo -n true 2>/dev/null; then
    log_error "sudo still works without a password"
    exit 1
fi
sync
log_info "Golden provisioning done"
