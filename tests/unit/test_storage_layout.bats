#!/usr/bin/env bats
# D22: the boot storage job and the storage wait must never act on an empty
# mount-point folder, and must never change existing data's owner or mode.
# Runs the real scripts against a fake /Volumes; a stub diskutil reports which
# folders are mounted volumes.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    SETUP="$ROOT/scripts/storage/setup_direct_mounts.sh"
    WAIT="$ROOT/scripts/storage/wait_for_storage.sh"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    export HOMELAB_VOLUMES_ROOT="$VOL" FAKE_MOUNTS="" TEST_MODE=1
    export CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    # diskutil info -plist PATH: a mounted volume reports itself as the mount
    # point; anything else fails, as the real diskutil does for a plain folder.
    cat >"$STUBS/diskutil" <<'EOF'
#!/usr/bin/env bash
path="${*: -1}"
for m in $FAKE_MOUNTS; do
    if [[ "$path" == "$m" ]]; then
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>MountPoint</key><string>%s</string></dict></plist>\n' "$m"
        exit 0
    fi
done
exit 1
EOF
    # sudo must never be needed; record it if anything tries.
    printf '#!/usr/bin/env bash\necho "sudo $*" >> "$CALLS"\nexit 1\n' >"$STUBS/sudo"
    chmod +x "$STUBS/diskutil" "$STUBS/sudo"
    export PATH="$STUBS:$PATH"
}

mount_tier() {
    mkdir -p "$VOL/$1"
    FAKE_MOUNTS="$FAKE_MOUNTS $VOL/$1"
}

mode_of() { stat -f '%Lp' "$1"; }

@test "an empty mount-point folder is skipped: nothing is created on the internal disk" {
    mkdir -p "$VOL/warmstore"   # left behind while the RAID is offline (D21)
    mount_tier faststore
    run "$SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warmstore is not mounted"* ]] || false
    [ -z "$(ls -A "$VOL/warmstore")" ]
    [ -d "$VOL/faststore/immich/upload" ]
}

@test "a missing tier is reported and the job still succeeds" {
    mount_tier faststore
    run "$SETUP"
    [ "$status" -eq 0 ]
    [ ! -e "$VOL/warmstore" ]
}

@test "existing data keeps its mode: the Postgres folder stays 0700" {
    mount_tier faststore
    mkdir -p "$VOL/faststore/immich/database" "$VOL/faststore/immich/upload/u1"
    chmod 700 "$VOL/faststore/immich/database"
    echo photo >"$VOL/faststore/immich/upload/u1/IMG_0001.jpg"
    chmod 600 "$VOL/faststore/immich/upload/u1/IMG_0001.jpg"
    run "$SETUP"
    [ "$status" -eq 0 ]
    [ "$(mode_of "$VOL/faststore/immich/database")" = 700 ]
    [ "$(mode_of "$VOL/faststore/immich/upload/u1/IMG_0001.jpg")" = 600 ]
}

@test "a new Immich database folder is created 0700" {
    mount_tier faststore
    run "$SETUP"
    [ "$status" -eq 0 ]
    [ "$(mode_of "$VOL/faststore/immich/database")" = 700 ]
    [ "$(mode_of "$VOL/faststore/immich/library")" = 755 ]
}

@test "the full layout is created on mounted tiers, and a second run changes nothing" {
    mount_tier faststore
    mount_tier warmstore
    run "$SETUP"
    [ "$status" -eq 0 ]
    [ -d "$VOL/warmstore/staging/tv-shows" ]
    [ -d "$VOL/faststore/plex/metadata" ]
    run "$SETUP"
    [ "$status" -eq 0 ]
    [[ "$output" == *"(0 folder(s) created)"* ]] || false
}

@test "dry run reports what it would create and creates nothing" {
    mount_tier faststore
    run "$SETUP" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create $VOL/faststore/immich/database (mode 700)"* ]] || false
    [ -z "$(ls -A "$VOL/faststore")" ]
}

@test "no sudo is ever called" {
    mount_tier faststore
    mkdir -p "$VOL/warmstore"
    run "$SETUP"
    [ "$status" -eq 0 ]
    [ ! -s "$CALLS" ]
}

@test "the scripts contain no sudo and no recursive chmod or chown" {
    for f in "$SETUP" "$WAIT" "$ROOT/scripts/storage/lib/mount_common.sh"; do
        run grep -nE '(^|[^#]*[;&|[:space:]])sudo |chmod -R|chown -R' "$f"
        [ "$status" -ne 0 ] || { echo "$f: $output"; false; }
    done
}

@test "wait_for_storage: a mounted faststore with its immich folder is ready" {
    mount_tier faststore
    mkdir -p "$VOL/faststore/immich"
    WAIT_TIMEOUT=2 WAIT_INTERVAL=1 run "$WAIT" faststore
    [ "$status" -eq 0 ]
    [[ "$output" == *"Storage ready: faststore"* ]] || false
}

@test "wait_for_storage: an empty mount-point folder is not ready" {
    mkdir -p "$VOL/warmstore"
    WAIT_TIMEOUT=2 WAIT_INTERVAL=1 run "$WAIT" warmstore
    [ "$status" -eq 1 ]
    [[ "$output" == *"warmstore not mounted"* ]] || false
}

@test "wait_for_storage: Immich waits only for faststore, so warmstore being offline doesn't block it" {
    mount_tier faststore
    mkdir -p "$VOL/faststore/immich"
    WAIT_TIMEOUT=2 WAIT_INTERVAL=1 run "$WAIT" faststore
    [ "$status" -eq 0 ]
    run grep -c 'wait_for_storage.sh faststore &amp;&amp;' "$ROOT/launchd/io.homelab.compose.immich.plist"
    [ "$output" = 1 ]
}

@test "wait_for_storage: no arguments waits for both tiers; an unknown tier is refused" {
    mount_tier faststore
    mkdir -p "$VOL/faststore/immich"
    WAIT_TIMEOUT=1 WAIT_INTERVAL=1 run "$WAIT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"warmstore not mounted"* ]] || false
    run "$WAIT" nvme
    [ "$status" -eq 2 ]
}
