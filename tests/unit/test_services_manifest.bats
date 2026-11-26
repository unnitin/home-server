#!/usr/bin/env bats
# services/ on the manifest: start_plex_safe.sh and start_jellyfin_safe.sh (run by
# LaunchD every couple of minutes) through lib/native_app.sh, and the landing port.
# Stubs stand in for curl, open, diskutil and tailscale; the apps folder and the
# tiers are temporary, so no real app, volume or tailnet mapping is touched.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS" "$BATS_TEST_TMPDIR/Applications/Plex Media Server.app" "$BATS_TEST_TMPDIR/Applications/Jellyfin.app"
    load ../test_helper
    unset $(compgen -v | grep '^HOMELAB_' || true)
    homelab_volumes_at "$VOL"
    export HOMELAB_APPS_DIR="$BATS_TEST_TMPDIR/Applications" START_TIMEOUT=3 START_INTERVAL=1 \
        CALLS="$BATS_TEST_TMPDIR/calls" FAKE_MOUNTS="" FAKE_DOWN_CHECKS=0 \
        CHECKS="$BATS_TEST_TMPDIR/checks" TS_STATE="$BATS_TEST_TMPDIR/serve.json" \
        TAILSCALE_BIN="$STUBS/tailscale" TS_NO_SUDO=1 TEST_MODE=1
    : >"$CALLS"; echo 0 >"$CHECKS"; echo '{"Web": {}}' >"$TS_STATE"
    # curl: the first FAKE_DOWN_CHECKS health checks fail, then the app answers
    # (FAKE_DOWN_CHECKS=-1: never answers)
    cat >"$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
n=$(( $(cat "$CHECKS") + 1 )); echo "$n" >"$CHECKS"
if [[ "$FAKE_DOWN_CHECKS" == -1 || "$n" -le "$FAKE_DOWN_CHECKS" ]]; then printf 000; exit 7; fi
printf 200
STUB
    printf '#!/usr/bin/env bash\necho "open $*" >> "$CALLS"\n' >"$STUBS/open"
    printf '#!/usr/bin/env bash\npath="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%%s</string></dict></plist>" "$m"; exit 0; }; done; exit 1\n' >"$STUBS/diskutil"
    cat >"$STUBS/tailscale" <<'STUB'
#!/usr/bin/env bash
echo "tailscale $*" >> "$CALLS"
case "$*" in
    "serve status --json") cat "$TS_STATE" ;;
    "status --json") echo '{"Self": {"DNSName": "mini.example.ts.net."}}' ;;
    "funnel status --json") echo '{}' ;;
esac
exit 0
STUB
    chmod +x "$STUBS"/*
    export PATH="$STUBS:$PATH"
    [ "$(command -v tailscale)" = "$STUBS/tailscale" ] && [ "$(command -v open)" = "$STUBS/open" ]
}

mount_faststore() { mkdir -p "$VOL/faststore"; FAKE_MOUNTS="$VOL/faststore"; }
map_plex() { echo '{"Web": {"mini.example.ts.net:32400": {"Handlers": {"/": {"Proxy": "http://localhost:32400"}}}}}' >"$TS_STATE"; }

@test "an app that already answers is left alone" {
    run bash "$ROOT/scripts/services/start_plex_safe.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already running and answering (http://localhost:32400/identity)"* ]] || false
    ! grep -q "^open" "$CALLS" || false
}

@test "it won't start an app whose data tier isn't mounted (D22)" {
    mkdir -p "$VOL/faststore"   # a folder, not a volume
    FAKE_DOWN_CHECKS=-1 run bash "$ROOT/scripts/services/start_jellyfin_safe.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"faststore is not mounted at $VOL/faststore: Jellyfin's data lives there"* ]] || false
    ! grep -q "^open" "$CALLS" || false
}

@test "a slow start is waited for, not abandoned at the first check (D30)" {
    mount_faststore
    FAKE_DOWN_CHECKS=3 run bash "$ROOT/scripts/services/start_plex_safe.sh"
    [ "$status" -eq 0 ]
    grep -q "open -a Plex Media Server" "$CALLS"
    [[ "$output" == *"Waiting for Plex Media Server"* && "$output" == *"started and answering"* ]] || false
}

@test "the tailnet mapping is taken down for the start and the manifest's put back" {
    mount_faststore; map_plex
    FAKE_DOWN_CHECKS=2 run bash "$ROOT/scripts/services/start_plex_safe.sh"
    [ "$status" -eq 0 ]
    off=$(grep -n "serve --https=32400 off" "$CALLS" | cut -d: -f1)
    opened=$(grep -n "^open" "$CALLS" | cut -d: -f1)
    [ -n "$off" ] && [ "$off" -lt "$opened" ]
    [[ "$output" == *"Restoring the tailnet mappings from the manifest"* ]] || false
    [[ "$output" == *"Dry run"* ]] || false   # apply_tailscale_serve.sh ran (TEST_MODE: dry run)
}

@test "mappings are put back even when the app never answers" {
    mount_faststore; map_plex
    FAKE_DOWN_CHECKS=-1 run bash "$ROOT/scripts/services/start_plex_safe.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Restoring the tailnet mappings"* && "$output" == *"did not answer"* ]] || false
}

@test "no mapping on the port: nothing is taken down" {
    mount_faststore
    FAKE_DOWN_CHECKS=1 run bash "$ROOT/scripts/services/start_jellyfin_safe.sh"
    [ "$status" -eq 0 ]
    ! grep -q "off" "$CALLS" || false
}

@test "a missing app is reported" {
    mount_faststore
    rm -r "$HOMELAB_APPS_DIR/Jellyfin.app"
    FAKE_DOWN_CHECKS=-1 run bash "$ROOT/scripts/services/start_jellyfin_safe.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Jellyfin.app not found"* ]] || false
}

@test "no counter in services/ uses ((n++)) under set -e (D30)" {
    ! grep -nE '\(\([A-Za-z_]+\+\+\)\)' "$ROOT"/scripts/services/*.sh "$ROOT"/scripts/services/lib/*.sh || false
}

@test "the landing page serves on the manifest's port" {
    ! grep -nE '[^A-Z_]8080' "$ROOT/scripts/services/enable_landing.sh" | grep -v '^[0-9]*:#' || false
    grep -q 'HOMELAB_SVC_LANDING_PORTS' "$ROOT/scripts/services/enable_landing.sh"
}
