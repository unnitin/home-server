#!/usr/bin/env bats
# diagnostics/ on the manifest: diag_lib.sh reads config/homelab.env directly
# (never scripts/), the caller's values win, built-in defaults cover a missing
# file, and the storage diagnostics use diskutil, not folder existence or df, to
# decide what's mounted (D31). Stub diskutil and df; a temporary /Volumes.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export FAKE_MOUNTS="" FAKE_USAGE="" CALLS="$BATS_TEST_TMPDIR/calls" NO_COLOR=1
    : >"$CALLS"
    printf '#!/usr/bin/env bash\ncase "$1" in info) path="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%%s</string></dict></plist>" "$m"; exit 0; }; done; exit 1;; *) exit 0;; esac\n' >"$STUBS/diskutil"
    printf '#!/usr/bin/env bash\necho "df $*" >> "$CALLS"\npath="${*: -1}"; pct=34; for kv in $FAKE_USAGE; do [[ "${kv%%%%=*}" == "$path" ]] && pct="${kv#*=}"; done\necho "Filesystem Size Used Avail Capacity Mounted"; echo "/dev/disk9s1 1.9Ti 1.0Ti 0.9Ti ${pct}%% $path"\n' >"$STUBS/df"
    chmod +x "$STUBS"/*
    export PATH="$STUBS:$PATH"
}

mount_tier() { mkdir -p "$VOL/$1"; FAKE_MOUNTS="$FAKE_MOUNTS $VOL/$1"; }

@test "diag_lib: the manifest's values, coldstore included" {
    unset $(compgen -v | grep '^HOMELAB_' || true)
    run bash -c 'source "$1"; diag_tier_mount coldstore x; echo "$HOMELAB_SVC_JELLYFIN_PORTS"' _ "$ROOT/diagnostics/diag_lib.sh"
    [ "${lines[0]}" = /Volumes/coldstore ] && [ "${lines[1]}" = 8096 ]
}

@test "diag_lib: a value the caller set wins" {
    run bash -c 'source "$1"; diag_tier_mount coldstore x' _ "$ROOT/diagnostics/diag_lib.sh"
    [ "$output" = "$VOL/coldstore" ]
}

@test "diag_lib: without homelab.env, the built-in default" {
    unset $(compgen -v | grep '^HOMELAB_' || true)
    mkdir -p "$BATS_TEST_TMPDIR/repo/diagnostics"
    cp "$ROOT/diagnostics/diag_lib.sh" "$BATS_TEST_TMPDIR/repo/diagnostics/"
    run bash -c 'source "$1"; diag_tier_mount coldstore /Volumes/fallback' _ "$BATS_TEST_TMPDIR/repo/diagnostics/diag_lib.sh"
    [ "$output" = /Volumes/fallback ]
}

@test "check_storage: an empty mount-point folder is not mounted, and nothing is written there (D31)" {
    mount_tier faststore
    mkdir -p "$VOL/warmstore"
    run bash "$ROOT/diagnostics/check_storage.sh"
    [[ "$output" == *"Mounted: $VOL/faststore"* ]] || false
    [[ "$output" == *"Not mounted (an empty mount-point folder): $VOL/warmstore"* ]] || false
    [[ "$output" == *"Not mounted, not tested: $VOL/warmstore"* ]] || false
    [ -z "$(ls -A "$VOL/warmstore")" ]
}

@test "verify_media_paths: an empty folder fails, df is never asked about it (D31)" {
    mount_tier faststore
    mkdir -p "$VOL/warmstore"
    run bash "$ROOT/diagnostics/verify_media_paths.sh"
    [[ "$output" == *"FAIL - Not mounted: the folder is an empty mount point"* ]] || false
    ! grep -q "df .*$VOL/warmstore" "$CALLS" || false
}

@test "verify_media_paths: coldstore not attached is a warning, not a failure" {
    mount_tier faststore; mount_tier warmstore
    run bash "$ROOT/diagnostics/verify_media_paths.sh"
    [[ "$output" == *"WARN - Not attached: $VOL/coldstore"* ]] || false
    [[ "$output" != *"FAIL - Directory does not exist: $VOL/coldstore"* ]] || false
}

@test "verify_media_paths: each tier's own thresholds from the manifest" {
    mount_tier faststore; mount_tier warmstore
    FAKE_USAGE="$VOL/faststore=82 $VOL/warmstore=82" run bash "$ROOT/diagnostics/verify_media_paths.sh"
    [ "$(grep -c '^WARN - High disk usage: at or above 80%' <<<"$output")" -eq 1 ]   # faststore warns at 80 (the summary repeats it)
    [[ "$output" != *"at or above 85%"* ]] || false                           # warmstore at 85: not yet
}
