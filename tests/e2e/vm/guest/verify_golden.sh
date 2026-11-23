#!/usr/bin/env bash
# Check that this VM still has everything provision_golden.sh set up. Runs
# INSIDE the VM: after the golden build reboots, and at the start of every
# rehearsal, so a lost or drifted setup fails loudly instead of skewing results.
#
#   verify_golden.sh
#
# Prints one line per check and exits 1 if any failed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=assert_vm.sh
source "$HERE/assert_vm.sh" || exit 3

FS=/Volumes/faststore
APPSUP="$HOME/Library/Application Support"
bad=0
check() {
    local what="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "ok    $what"
    else
        echo "FAIL  $what"
        bad=1
    fi
}
mode_is() { [[ "$(stat -f '%Lp' "$2")" == "$1" ]]; }
# No warmstore volume, and nothing the user can write there. macOS removes the
# empty /Volumes/warmstore folder at boot, so it may be absent; jobs then fail
# with the same "Permission denied" as on the mini.
warmstore_unusable() {
    ! /sbin/mount | grep -q ' on /Volumes/warmstore ' &&
        [[ ! -w /Volumes/warmstore && ! -w /Volumes ]]
}
link_to() { [[ -L "$1" && "$(readlink "$1")" == "$2" ]]; }
no_sudo() { ! sudo -n true; }
displaysleep_1() { pmset -g custom | grep -Eq '^[[:space:]]*displaysleep[[:space:]]+1$'; }
mcp_installed() { /opt/homebrew/bin/python3.11 -c 'import mcp, uvicorn, starlette'; }

check "faststore mounted" test -d "$FS/immich"
check "faststore layout" test -d "$FS/immich/upload" -a -d "$FS/plex/metadata" -a -d "$FS/jellyfin/config"
check "Immich database folder is 0700" mode_is 700 "$FS/immich/database"
check "fixture backup present" test -s "$FS/immich/backups/immich-db-backup-20260101T020000-v2.1.0-pg16.10.sql.gz"
check "Plex data folder is a symlink into faststore" link_to "$APPSUP/Plex Media Server" "$FS/plex/metadata"
check "Jellyfin data folder is a symlink into faststore" link_to "$APPSUP/jellyfin" "$FS/jellyfin/config"
check "warmstore offline and not writable (D21)" warmstore_unusable
check "sudo needs a password" no_sudo
check "display sleep 1, as on the mini" displaysleep_1
check "Python 3.11 with the MCP packages" mcp_installed
check "Plex Media Server.app" test -d "/Applications/Plex Media Server.app"
check "Jellyfin.app" test -d /Applications/Jellyfin.app
exit "$bad"
