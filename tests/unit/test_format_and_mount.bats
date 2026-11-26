#!/usr/bin/env bats
# D29: format_and_mount.sh must never erase a RAID set that holds a file system,
# must erase a blank one only with RAID_I_UNDERSTAND_DATA_LOSS=1, and must never
# create a mount-point folder. A stub diskutil fakes the RAID sets, file systems
# and APFS containers; TEST_MODE=1 makes the script print mount and erase
# commands instead of running them, and the stub records any it does receive.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    SCRIPT="$ROOT/scripts/storage/format_and_mount.sh"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export CALLS="$BATS_TEST_TMPDIR/calls" TEST_MODE=1 RAID_I_UNDERSTAND_DATA_LOSS=0
    # FAKE_RAIDS="name:dev"  FAKE_FS="dev:type"  FAKE_APFS="store:vol:name"
    # FAKE_VOLMOUNT="vol:mountpoint"  FAKE_MOUNTS="path" (for the layout step)
    export FAKE_RAIDS="" FAKE_FS="" FAKE_APFS="" FAKE_VOLMOUNT="" FAKE_MOUNTS=""
    : >"$CALLS"
    cat >"$STUBS/diskutil" <<'STUB'
#!/usr/bin/env bash
plist() { printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>%s</dict></plist>\n' "$1"; }
case "$1 ${2:-}" in
"appleRAID list")
    for r in $FAKE_RAIDS; do printf '  Name:                 %s\n  Status:               Online\n  Device Node:          %s\n' "${r%%:*}" "${r#*:}"; done ;;
"info -plist")
    path="$3"; dev="${path#/dev/}"; body=""
    for f in $FAKE_FS; do [[ "${f%%:*}" == "$dev" ]] && body="<key>FilesystemType</key><string>${f#*:}</string>"; done
    for m in $FAKE_VOLMOUNT; do [[ "${m%%:*}" == "$dev" ]] && body="$body<key>MountPoint</key><string>${m#*:}</string>"; done
    for m in $FAKE_MOUNTS; do [[ "$m" == "$path" ]] && body="<key>MountPoint</key><string>$m</string>"; done
    [[ -n "$body" ]] || exit 1
    plist "$body" ;;
"apfs list")
    c=""
    for a in $FAKE_APFS; do
        IFS=: read -r store vol name <<<"$a"
        c="$c<dict><key>ContainerReference</key><string>c$store</string><key>PhysicalStores</key><array><dict><key>DeviceIdentifier</key><string>$store</string></dict></array><key>Volumes</key><array>"
        [[ -n "$vol" ]] && c="$c<dict><key>DeviceIdentifier</key><string>$vol</string><key>Name</key><string>$name</string></dict>"
        c="$c</array></dict>"
    done
    plist "<key>Containers</key><array>$c</array>" ;;
*)
    echo "diskutil $*" >>"$CALLS" ;;   # anything that changes state
esac
STUB
    printf '#!/usr/bin/env bash\necho "sudo $*" >> "$CALLS"\nexit 1\n' >"$STUBS/sudo"
    chmod +x "$STUBS/diskutil" "$STUBS/sudo"
    export PATH="$STUBS:$PATH"
    # Refuse to run unless every diskutil call goes to the stub
    [ "$(command -v diskutil)" = "$STUBS/diskutil" ]
}

@test "an APFS set mounted where the manifest says is left alone" {
    FAKE_RAIDS="faststore:disk8" FAKE_FS="disk8:apfs" FAKE_APFS="disk8:disk9s1:faststore" \
        FAKE_VOLMOUNT="disk9s1:$VOL/faststore" FAKE_MOUNTS="$VOL/faststore" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"disk9s1 ('faststore') is mounted at $VOL/faststore"* ]] || false
    [[ "$output" != *"would run"* ]] || false
}

@test "an unmounted APFS set is mounted by diskutil, never into a folder we make (D25)" {
    mkdir -p "$VOL"   # the tier's mount point doesn't exist
    FAKE_RAIDS="faststore:disk8" FAKE_FS="disk8:apfs" FAKE_APFS="disk8:disk9s1:faststore" run bash "$SCRIPT"
    [[ "$output" == *"would run: diskutil mount /dev/disk9s1"* ]] || false
    [ ! -e "$VOL/faststore" ]
}

@test "a volume named Archive gets rename advice, not an erase" {
    FAKE_RAIDS="coldstore:disk12" FAKE_FS="disk12:apfs" FAKE_APFS="disk12:disk13s1:Archive" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"named 'Archive', so it mounts at /Volumes/Archive"* ]] || false
    [[ "$output" == *"diskutil rename /dev/disk13s1 coldstore"* ]] || false
    [[ "$output" != *"eraseVolume"* ]] || false
}

@test "an APFS set whose volume can't be found is never erased (D29)" {
    RAID_I_UNDERSTAND_DATA_LOSS=1 FAKE_RAIDS="faststore:disk8" FAKE_FS="disk8:apfs" FAKE_APFS="disk8::" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"holds APFS, but no volume was found on it. Not erasing it."* ]] || false
    [[ "$output" != *"eraseVolume"* ]] || false
}

@test "an APFS set found only by its content type is still never erased (D29)" {
    RAID_I_UNDERSTAND_DATA_LOSS=1 FAKE_RAIDS="faststore:disk8" FAKE_FS="disk8:apfs" run bash "$SCRIPT"
    [[ "$output" != *"eraseVolume"* ]] || false
}

@test "a set holding another file system is never erased, even with the flag" {
    RAID_I_UNDERSTAND_DATA_LOSS=1 FAKE_RAIDS="warmstore:disk10" FAKE_FS="disk10:hfs" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"holds hfs, not APFS. It holds data: not erasing it."* ]] || false
    [[ "$output" != *"eraseVolume"* ]] || false
}

@test "a blank set is not erased without RAID_I_UNDERSTAND_DATA_LOSS=1" {
    FAKE_RAIDS="warmstore:disk10" run bash "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"has no file system. Formatting it erases the set."* ]] || false
    [[ "$output" != *"eraseVolume"* ]] || false
}

@test "a blank set is erased as APFS named after its tier with the flag" {
    RAID_I_UNDERSTAND_DATA_LOSS=1 FAKE_RAIDS="warmstore:disk10" run bash "$SCRIPT"
    [[ "$output" == *"would run: diskutil eraseVolume APFS warmstore /dev/disk10"* ]] || false
}

@test "no RAID sets: every tier is skipped and nothing changes" {
    run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(skip) no RAID set named 'faststore'"* ]] || false
    [[ "$output" != *"would run"* ]] || false
}

@test "TEST_MODE: no mount, erase or sudo ever reaches diskutil" {
    RAID_I_UNDERSTAND_DATA_LOSS=1 FAKE_RAIDS="faststore:disk8 warmstore:disk10" FAKE_FS="disk8:apfs" FAKE_APFS="disk8:disk9s1:faststore" run bash "$SCRIPT"
    [ ! -s "$CALLS" ]
}

@test "the script contains no sudo, mkdir or -mountPoint" {
    ! grep -nE '^[^#]*\b(sudo|mkdir)\b|-mountPoint' "$SCRIPT" || false
}
