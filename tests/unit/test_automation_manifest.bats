#!/usr/bin/env bats
# automation/ on the manifest: configure_launchd.sh installs the manifest's jobs in
# boot order, one job on request, keeps held jobs held and won't load jobs from a
# linked worktree; setup_media_processing.sh builds on the storage and LaunchD
# scripts. A stub launchctl records every call (and must be the one on PATH); plists
# render into a temporary folder; tiers move to a temporary /Volumes.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    LAUNCHD="$ROOT/scripts/automation/configure_launchd.sh"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export LAUNCHD_PLIST_DIR="$BATS_TEST_TMPDIR/agents" CALLS="$BATS_TEST_TMPDIR/calls" \
        FAKE_DISABLED="$BATS_TEST_TMPDIR/disabled" FAKE_MOUNTS="" TEST_MODE=0 \
        HOMELAB_ALLOW_WORKTREE=1
    : >"$CALLS"; : >"$FAKE_DISABLED"
    cat >"$STUBS/launchctl" <<'STUB'
#!/usr/bin/env bash
echo "launchctl $*" >> "$CALLS"
[[ "$1" == print-disabled ]] && cat "$FAKE_DISABLED"
exit 0
STUB
    printf '#!/usr/bin/env bash\npath="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%%s</string></dict></plist>" "$m"; exit 0; }; done; exit 1\n' >"$STUBS/diskutil"
    chmod +x "$STUBS"/*
    export PATH="$STUBS:$PATH"
    [ "$(command -v launchctl)" = "$STUBS/launchctl" ]
}

installed_order() { sed -n 's/^📦 Installing service: io\.homelab\.//p' <<<"$output" | tr '\n' ' '; }

@test "launchd: every job in the manifest, in boot order" {
    run bash "$LAUNCHD" --render-only
    [ "$status" -eq 0 ]
    want=""
    for j in $(bash -c 'source "$1"; echo "$HOMELAB_LAUNCHD_SERVICES"' _ "$ROOT/scripts/core/environment.sh"); do
        [[ "$j" == tailscale && ! -x /opt/homebrew/sbin/tailscaled ]] && continue
        want="$want$j "
    done
    [ "$(installed_order)" = "$want" ]
    ! grep -lE '__[A-Z]+__' "$LAUNCHD_PLIST_DIR"/*.plist || false
}

@test "launchd: one job on request, and an unknown one is refused" {
    run bash "$LAUNCHD" --render-only media.watcher
    [ "$(installed_order)" = "media.watcher " ]
    run bash "$LAUNCHD" --render-only nonsense
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown job: nonsense"* ]] || false
}

@test "launchd: a held job stays held; the others load" {
    printf '\t"io.homelab.media.watcher" => disabled\n' >"$FAKE_DISABLED"
    run bash "$LAUNCHD" media.watcher mcp
    [ "$status" -eq 0 ]
    [[ "$output" == *"Held: io.homelab.media.watcher is disabled"* ]] || false
    ! grep -q "bootstrap .*io.homelab.media.watcher.plist" "$CALLS" || false
    ! grep -q "enable gui/.*/io.homelab.media.watcher" "$CALLS" || false
    grep -q "bootstrap .*io.homelab.mcp.plist" "$CALLS"
}

@test "launchd: jobs are never loaded from a linked worktree" {
    git -C "$BATS_TEST_TMPDIR" init -q main
    git -C "$BATS_TEST_TMPDIR/main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git -C "$BATS_TEST_TMPDIR/main" worktree add -q "$BATS_TEST_TMPDIR/wt"
    mkdir -p "$BATS_TEST_TMPDIR/wt/scripts"
    cp -R "$ROOT/scripts/automation" "$ROOT/scripts/core" "$BATS_TEST_TMPDIR/wt/scripts/"
    cp -R "$ROOT/config" "$ROOT/launchd" "$BATS_TEST_TMPDIR/wt/"
    HOMELAB_ALLOW_WORKTREE=0 run bash "$BATS_TEST_TMPDIR/wt/scripts/automation/configure_launchd.sh" mcp
    [ "$status" -eq 2 ]
    [[ "$output" == *"is a linked git worktree"* ]] || false
    ! grep -q bootstrap "$CALLS" || false
}

@test "media setup: refuses while the media tier isn't mounted" {
    mkdir -p "$VOL/warmstore"   # a folder, not a volume
    run bash "$ROOT/scripts/automation/setup_media_processing.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"$VOL/warmstore is not mounted"* ]] || false
    [ ! -e "$VOL/warmstore/staging" ]
}

@test "media setup: the manifest's staging folders and the watcher job" {
    mkdir -p "$VOL/warmstore"; FAKE_MOUNTS="$VOL/warmstore"
    run bash "$ROOT/scripts/automation/setup_media_processing.sh"
    [ "$status" -eq 0 ]
    [ -d "$VOL/warmstore/staging/tv-shows" ] && [ -d "$VOL/warmstore/staging/failed" ]
    [ -f "$LAUNCHD_PLIST_DIR/io.homelab.media.watcher.plist" ]
    ! grep -qE '__[A-Z]+__' "$LAUNCHD_PLIST_DIR/io.homelab.media.watcher.plist" || false
    [[ "$output" == *"TV Shows:    $VOL/warmstore/staging/tv-shows/"* ]] || false
}

@test "update check: Immich's address defaults to the manifest's port" {
    grep -q 'IMMICH_SERVER:-http://localhost:${HOMELAB_SVC_IMMICH_PORTS' "$ROOT/scripts/automation/check_updates.sh"
}
