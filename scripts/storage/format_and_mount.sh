#!/usr/bin/env bash
# Mount each storage tier's AppleRAID set where the manifest (config/homelab.yaml)
# says. Formats a set only when it holds no file system and you confirm data loss.
#
#   ./scripts/storage/format_and_mount.sh
#   RAID_I_UNDERSTAND_DATA_LOSS=1 ./scripts/storage/format_and_mount.sh   # may erase a BLANK set
#
# For each tier whose RAID set exists (sets are named after their tier):
#   - APFS, mounted where the manifest says: nothing to do
#   - APFS, not mounted: diskutil mount (diskutil makes the mount point)
#   - APFS, volume named differently: says how to rename it (diskutil mounts a
#     volume at /Volumes/<its name>)
#   - APFS, but its volume can't be found: refuses. Never erases it (D29)
#   - any other file system: refuses. It holds data
#   - no file system at all: erases it as APFS, only with RAID_I_UNDERSTAND_DATA_LOSS=1
#
# Never creates a folder where a volume should be (D25).
# TEST_MODE=1 prints the mount and erase commands instead of running them.
# Exit: 0 = every present set is mounted where the manifest says; 1 = anything else.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../core/environment.sh
source "${SCRIPT_DIR}/../core/environment.sh"

APFS_GUID="7C3457EF-0000-11AA-AA11-00306543ECAC"
problems=0

# Destructive or state-changing diskutil calls go through here.
run_disk() {
    if [[ "${TEST_MODE:-0}" == "1" ]]; then
        echo "   TEST_MODE: would run: diskutil $*"
    else
        diskutil "$@"
    fi
}

plist_get() {  # plist_get KEYPATH  (plist on stdin); prints nothing on failure
    local out
    # plutil reports a parse error on stdout, so keep its output only on success
    out=$(plutil -extract "$1" raw -o - - 2>/dev/null) || return 1
    printf '%s\n' "$out"
}

# BSD device of the RAID set with this name (e.g. disk8), or nothing
raid_device() {
    diskutil appleRAID list 2>/dev/null | awk -v want="$1" '
        /^ *Name:/        { name = $0; sub(/^ *Name:[ ]*/, "", name); hit = (name == want); next }
        hit && /^ *Device Node:/ { dev = $0; sub(/^ *Device Node:[ ]*/, "", dev); print dev; exit }'
}

# "apfs", another file system type, or nothing when the set is blank
filesystem_of() {
    local info content fs
    info=$(diskutil info -plist "/dev/$1" 2>/dev/null) || return 0
    content=$(plist_get Content <<<"$info" || true)
    fs=$(plist_get FilesystemType <<<"$info" || true)
    if [[ "$content" == "$APFS_GUID" || "$fs" == apfs ]]; then
        echo apfs
    else
        echo "${fs:-}"
    fi
}

# "DEVICE NAME" of the first volume in the APFS container on this physical store
apfs_volume_on() {
    local store="$1" list i j k dev
    list=$(diskutil apfs list -plist 2>/dev/null) || return 0
    for ((i = 0; ; i++)); do
        plist_get "Containers.$i.ContainerReference" <<<"$list" >/dev/null || return 0
        for ((j = 0; ; j++)); do
            dev=$(plist_get "Containers.$i.PhysicalStores.$j.DeviceIdentifier" <<<"$list") || break
            [[ "$dev" == "$store" ]] || continue
            for ((k = 0; ; k++)); do
                dev=$(plist_get "Containers.$i.Volumes.$k.DeviceIdentifier" <<<"$list") || return 0
                echo "$dev $(plist_get "Containers.$i.Volumes.$k.Name" <<<"$list" || true)"
                return 0
            done
        done
    done
}

handle_tier() {
    local tier="$1" mount dev fs vol name current
    mount=$(homelab_tier_mount "$tier")
    echo "-- $tier: RAID set '$tier' -> $mount"

    dev=$(raid_device "$tier")
    if [[ -z "$dev" ]]; then
        echo "   (skip) no RAID set named '$tier'"
        return 0
    fi

    fs=$(filesystem_of "$dev")
    case "$fs" in
        apfs)
            read -r vol name <<<"$(apfs_volume_on "$dev")"
            if [[ -z "${vol:-}" ]]; then
                echo "   ❌ /dev/$dev holds APFS, but no volume was found on it. Not erasing it."
                echo "      Look with: diskutil apfs list"
                problems=$((problems + 1))
                return 0
            fi
            current=$(diskutil info -plist "/dev/$vol" 2>/dev/null | plist_get MountPoint || true)
            if [[ "$current" == "$mount" ]]; then
                echo "   ✅ $vol ('$name') is mounted at $mount"
            elif [[ "$name" != "$(basename "$mount")" ]]; then
                echo "   ⚠️  $vol is named '$name', so it mounts at /Volumes/$name, not $mount."
                echo "      Rename it (keeps the data): diskutil rename /dev/$vol $(basename "$mount")"
                problems=$((problems + 1))
            elif [[ -n "$current" ]]; then
                echo "   ⚠️  $vol is mounted at $current, not $mount. Unmount it and run this again."
                problems=$((problems + 1))
            else
                echo "   Mounting $vol ('$name')..."
                run_disk mount "/dev/$vol" || { echo "   ❌ mount failed"; problems=$((problems + 1)); }
            fi
            ;;
        "")
            if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
                echo "   ❌ /dev/$dev has no file system. Formatting it erases the set."
                echo "      To format it: RAID_I_UNDERSTAND_DATA_LOSS=1 $0"
                problems=$((problems + 1))
                return 0
            fi
            echo "   Erasing blank /dev/$dev as APFS '$tier'..."
            run_disk eraseVolume APFS "$tier" "/dev/$dev" ||
                { echo "   ❌ erase failed"; problems=$((problems + 1)); }
            ;;
        *)
            echo "   ❌ /dev/$dev holds $fs, not APFS. It holds data: not erasing it."
            problems=$((problems + 1))
            ;;
    esac
}

for tier in $HOMELAB_TIERS; do
    handle_tier "$tier"
done

echo ""
echo "=== Mounts ==="
for tier in $HOMELAB_TIERS; do
    mount=$(homelab_tier_mount "$tier")
    if [[ -z "$(raid_device "$tier")" ]]; then
        echo "⚪ $tier: no RAID set"
    elif [[ "${TEST_MODE:-0}" == "1" ]] || homelab_is_mounted "$mount"; then
        echo "✅ $tier: $mount"
    else
        echo "❌ $tier: not mounted at $mount"
        problems=$((problems + 1))
    fi
done

echo ""
echo "Setting up directory structure..."
if [[ "${TEST_MODE:-0}" == "1" ]]; then
    "$SCRIPT_DIR/setup_direct_mounts.sh" --dry-run || problems=$((problems + 1))
else
    "$SCRIPT_DIR/setup_direct_mounts.sh" || problems=$((problems + 1))
fi

if ((problems)); then
    echo "❌ $problems problem(s) above"
    exit 1
fi
echo "✅ Every present RAID set is mounted where the manifest says"
