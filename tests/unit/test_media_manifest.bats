#!/usr/bin/env bats
# media/ on the manifest: the processor and the watcher use the manifest's
# kebab-case layout (D10), write nothing unless the media tier is mounted (D26),
# keep going past a bad file with correct counts (D30), and the watcher actually
# runs the processor. Real scripts against a temporary /Volumes; a stub diskutil
# says which tiers are mounted.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    W="$VOL/warmstore"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export FAKE_MOUNTS="" WAIT_TIMEOUT=0 TEST_MODE=1
    printf '#!/usr/bin/env bash\npath="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%%s</string></dict></plist>" "$m"; exit 0; }; done; exit 1\n' >"$STUBS/diskutil"
    chmod +x "$STUBS/diskutil"
    export PATH="$STUBS:$PATH"
}

mount_media() {
    FAKE_MOUNTS="$W"
    for d in movies tv-shows collections staging/movies staging/tv-shows staging/collections staging/failed; do
        mkdir -p "$W/$d"
    done
}
stage() { echo x >"$W/staging/$1/$2"; }

@test "processor: an unmounted media tier is refused and nothing is written (D26)" {
    mkdir -p "$W"   # a folder, not a volume
    run bash "$ROOT/scripts/media/processor.sh" --all
    [ "$status" -eq 1 ]
    [[ "$output" == *"$W is not mounted: nothing processed, nothing written"* ]] || false
    [ -z "$(ls -A "$W")" ]
}

@test "processor: files land in the manifest's kebab-case folders (D10)" {
    mount_media
    stage movies "The.Matrix.1999.1080p.BluRay.mkv"
    stage tv-shows "Breaking.Bad.S01E02.720p.mkv"
    run bash "$ROOT/scripts/media/processor.sh" --all
    [ "$status" -eq 0 ]
    [ -f "$W/movies/The Matrix (1999)/The Matrix (1999).mkv" ]
    [ -f "$W/tv-shows/Breaking Bad/Season 01/Breaking Bad - s01e02.mkv" ]
    ! ls "$W" | grep -qxE 'Movies|TV Shows|Staging' || false
}

@test "processor: a bad file goes to staging/failed and the run carries on, counting right (D30)" {
    mount_media
    stage tv-shows "random clip.mkv"
    stage tv-shows "Breaking.Bad.S01E02.720p.mkv"
    stage tv-shows "The Office - s02e05.mkv"
    stage movies "Blade.Runner.2049.2017.2160p.mkv"
    stage movies "The.Matrix.1999.1080p.BluRay.mkv"
    run bash "$ROOT/scripts/media/processor.sh" --all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Movies processing complete: 2 processed, 0 failed"* ]] || false
    [[ "$output" == *"TV shows processing complete: 2 processed, 1 failed"* ]] || false
    ls "$W"/staging/failed/*/"random clip.mkv"
}

@test "processor: a single kind runs without a log folder yet" {
    mount_media
    stage movies "The.Matrix.1999.1080p.BluRay.mkv"
    [ ! -e "$W/logs" ]
    run bash "$ROOT/scripts/media/processor.sh" --movies-only
    [ "$status" -eq 0 ]
    [ -d "$W/logs/media-watcher" ] && [ -f "$W/movies/The Matrix (1999)/The Matrix (1999).mkv" ]
}

@test "processor: release names with dots, dashes or spaces before SxxEyy parse" {
    mount_media
    stage tv-shows "Show.Name.s03e10.mkv"
    stage tv-shows "Show_Name_S03E11_x265.mkv"
    run bash "$ROOT/scripts/media/processor.sh" --tv-only
    [ -f "$W/tv-shows/Show Name/Season 03/Show Name - s03e10.mkv" ]
    [ -f "$W/tv-shows/Show Name/Season 03/Show Name - s03e11.mkv" ]
}

@test "watcher: waits for the media tier and writes nothing while it's away (D26)" {
    mkdir -p "$W"
    run bash "$ROOT/scripts/media/watcher.sh" start
    [ "$status" -eq 1 ]
    [[ "$output" == *"warmstore not mounted at $W"* ]] || false
    [ -z "$(ls -A "$W")" ]
}

@test "watcher: status writes nothing" {
    mkdir -p "$W"
    run bash "$ROOT/scripts/media/watcher.sh" status
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$W")" ]
}

@test "watcher: runs the processor with --all (with no option it only prints usage)" {
    [ "$(grep -c '"$SCRIPT_DIR/processor.sh" --all' "$ROOT/scripts/media/watcher.sh")" -eq 2 ]
    ! grep -qE '"\$SCRIPT_DIR/processor.sh";' "$ROOT/scripts/media/watcher.sh" || false
}

@test "no counter in media/ uses ((n++)) under set -e (D30)" {
    ! grep -nE '\(\([A-Za-z_]+\+\+\)\)' "$ROOT"/scripts/media/*.sh || false
}
