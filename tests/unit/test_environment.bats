#!/usr/bin/env bats
# scripts/core/environment.sh (D12): every HOMELAB_* value from config/homelab.env,
# local overrides, values set by the caller winning, and the repo's physical path.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    ENVSH="$ROOT/scripts/core/environment.sh"
    # A throwaway checkout: the real environment.sh and homelab.env, nothing else
    FAKE="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$FAKE/scripts/core" "$FAKE/config"
    cp "$ENVSH" "$FAKE/scripts/core/"
    cp "$ROOT/config/homelab.env" "$FAKE/config/"
    unset $(compgen -v | grep '^HOMELAB_' || true)
}

@test "sources under macOS bash 3.2 with set -euo pipefail" {
    run /bin/bash -c 'set -euo pipefail; source "$1"; echo "$HOMELAB_TIER_COLDSTORE_MOUNT|$HOMELAB_MEDIA_TV_DIR"' _ "$ENVSH"
    [ "$status" -eq 0 ]
    [ "$output" = "/Volumes/coldstore|/Volumes/warmstore/tv-shows" ]
}

@test "HOMELAB_REPO is this checkout" {
    run bash -c 'source "$1"; echo "$HOMELAB_REPO"' _ "$ENVSH"
    [ "$output" = "$ROOT" ]
}

@test "HOMELAB_REPO is the physical path when reached through a symlink (D19)" {
    ln -s "$FAKE" "$BATS_TEST_TMPDIR/link"
    run bash -c 'source "$1"; echo "$HOMELAB_REPO"' _ "$BATS_TEST_TMPDIR/link/scripts/core/environment.sh"
    [ "$output" = "$(cd "$FAKE" && pwd -P)" ]
}

@test "values are exported to child processes" {
    run bash -c 'source "$1"; bash -c "echo \$HOMELAB_PHOTOS_LIBRARY"' _ "$ENVSH"
    [ "$output" = "/Volumes/faststore/immich" ]
}

@test "home-relative paths expand to the caller's HOME" {
    run env HOME=/home/test bash -c 'source "$1"; echo "$HOMELAB_STATE_DIR"' _ "$ENVSH"
    [ "$output" = "/home/test/Library/Application Support/homelab" ]
}

@test "a value set by the caller wins over homelab.env" {
    run env HOMELAB_MEDIA_TV_DIR=/tmp/tv bash -c 'source "$1"; echo "$HOMELAB_MEDIA_TV_DIR|$HOMELAB_MEDIA_MOVIES_DIR"' _ "$ENVSH"
    [ "$output" = "/tmp/tv|/Volumes/warmstore/movies" ]
}

@test "homelab.local.env overrides homelab.env" {
    echo 'HOMELAB_TIER_WARMSTORE_MOUNT="/Volumes/media2"' > "$FAKE/config/homelab.local.env"
    run bash -c 'source "$1"; echo "$HOMELAB_TIER_WARMSTORE_MOUNT|$HOMELAB_TIER_FASTSTORE_MOUNT"' _ "$FAKE/scripts/core/environment.sh"
    [ "$output" = "/Volumes/media2|/Volumes/faststore" ]
}

@test "the caller still wins over homelab.local.env" {
    echo 'HOMELAB_TIER_WARMSTORE_MOUNT="/Volumes/media2"' > "$FAKE/config/homelab.local.env"
    run env HOMELAB_TIER_WARMSTORE_MOUNT=/tmp/w bash -c 'source "$1"; echo "$HOMELAB_TIER_WARMSTORE_MOUNT"' _ "$FAKE/scripts/core/environment.sh"
    [ "$output" = "/tmp/w" ]
}

@test "a caller can't redirect HOMELAB_REPO" {
    run env HOMELAB_REPO=/elsewhere bash -c 'source "$1"; echo "$HOMELAB_REPO"' _ "$ENVSH"
    [ "$output" = "$ROOT" ]
}

@test "a missing homelab.env fails the caller under set -e, with the fix" {
    rm "$FAKE/config/homelab.env"
    run bash -c 'set -e; source "$1"; echo "should not get here"' _ "$FAKE/scripts/core/environment.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"homelab.env is missing"* ]] || false
    [[ "$output" == *"homelab config render"* ]] || false
    [[ "$output" != *"should not get here"* ]] || false
}

@test "homelab_tier_mount names a tier's mount point" {
    run bash -c 'source "$1"; homelab_tier_mount warmstore; homelab_tier_mount coldstore' _ "$ENVSH"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '/Volumes/warmstore\n/Volumes/coldstore')" ]
}

@test "homelab_tier_mount refuses an unknown tier" {
    run bash -c 'source "$1"; homelab_tier_mount archive' _ "$ENVSH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown tier 'archive'"* ]] || false
}
