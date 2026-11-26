#!/usr/bin/env bats
# takeout/ on the manifest: the import wrapper's default folders come from the
# manifest, and it won't create its output folder on a tier that isn't mounted.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    SCRIPT="$ROOT/scripts/takeout/enhanced_takeout_import.sh"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS" "$BATS_TEST_TMPDIR/takeout"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export FAKE_MOUNTS="" TEST_MODE=1
    printf '#!/usr/bin/env bash\npath="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%%s</string></dict></plist>" "$m"; exit 0; }; done; exit 1\n' >"$STUBS/diskutil"
    chmod +x "$STUBS/diskutil"
    export PATH="$STUBS:$PATH"
    touch "$BATS_TEST_TMPDIR/takeout/takeout-001.zip"
}

@test "takeout: the default folders are the manifest's" {
    run bash "$SCRIPT" --help
    [[ "$output" == *"(default: $VOL/faststore/takeout-downloads)"* ]] || false
    [[ "$output" == *"(default: $VOL/faststore/tmp/takeout-processed)"* ]] || false
}

@test "takeout: no output folder on a tier that isn't mounted (D22)" {
    mkdir -p "$VOL/faststore"   # a folder, not a volume
    run bash "$SCRIPT" -i "$BATS_TEST_TMPDIR/takeout" -o "$VOL/faststore/tmp/out" \
        --skip-upload --skip-deps --skip-system-deps
    [ "$status" -ne 0 ]
    [[ "$output" == *"faststore is not mounted at $VOL/faststore"* ]] || false
    [ ! -e "$VOL/faststore/tmp" ]
}
