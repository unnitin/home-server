#!/usr/bin/env bats
# core/ on the manifest: health_check.sh and check_storage_usage.sh take every
# job, tier, threshold and URL from config/homelab.yaml (through environment.sh).
# Stub tools stand in for launchctl, diskutil, df, curl, colima, docker, open and
# tailscale; tiers point at a temporary /Volumes, so nothing real is touched.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    HEALTH="$ROOT/scripts/core/health_check.sh"
    USAGE="$ROOT/scripts/core/check_storage_usage.sh"
    VOL="$BATS_TEST_TMPDIR/Volumes"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$VOL" "$STUBS"
    unset $(compgen -v | grep '^HOMELAB_' || true)
    export HOMELAB_TIER_FASTSTORE_MOUNT="$VOL/faststore" \
        HOMELAB_TIER_WARMSTORE_MOUNT="$VOL/warmstore" \
        HOMELAB_TIER_COLDSTORE_MOUNT="$VOL/coldstore"
    export CALLS="$BATS_TEST_TMPDIR/calls" FAKE_MOUNTS="" FAKE_USAGE="" FAKE_UP="" \
        FAKE_LIST="$BATS_TEST_TMPDIR/list" FAKE_DISABLED="$BATS_TEST_TMPDIR/disabled" \
        FAKE_COLIMA=1 TEST_MODE=1
    : >"$CALLS"; : >"$FAKE_LIST"; : >"$FAKE_DISABLED"

    stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUBS/$1"; chmod +x "$STUBS/$1"; }
    stub diskutil 'path="${*: -1}"; for m in $FAKE_MOUNTS; do [[ "$path" == "$m" ]] && { printf "<plist><dict><key>MountPoint</key><string>%s</string></dict></plist>\n" "$m"; exit 0; }; done; exit 1'
    # FAKE_USAGE="path=pct ...": df -P prints the percent, df -h fixed sizes
    stub df 'echo "df $*" >> "$CALLS"; path="${*: -1}"; pct=0; for kv in $FAKE_USAGE; do [[ "${kv%%=*}" == "$path" ]] && pct="${kv#*=}"; done; echo "Filesystem Size Used Avail Capacity Mounted"; echo "/dev/disk9s1 1.9Ti 1.0Ti 0.9Ti ${pct}% $path"'
    stub launchctl 'echo "launchctl $*" >> "$CALLS"; case "$1" in list) echo "PID Status Label"; cat "$FAKE_LIST";; print-disabled) cat "$FAKE_DISABLED";; esac; exit 0'
    # FAKE_UP: URLs that answer 200
    stub curl 'for a in "$@"; do case "$a" in http*) u="$a";; esac; done; for x in $FAKE_UP; do [[ "$x" == "$u" ]] && { printf 200; exit 0; }; done; printf 000; exit 7'
    stub colima 'echo "colima $*" >> "$CALLS"; [[ "$1" == status ]] && exit $(( 1 - FAKE_COLIMA )); exit 0'
    stub docker '[[ "$FAKE_COLIMA" == 1 ]]'
    stub open 'echo "open $*" >> "$CALLS"'
    stub tailscale 'echo "{\"Self\": {\"DNSName\": \"mini.example.ts.net.\"}}"'
    export PATH="$STUBS:$PATH"
}

mount_tier() { mkdir -p "$VOL/$1"; FAKE_MOUNTS="$FAKE_MOUNTS $VOL/$1"; }
all_up() {
    FAKE_UP="http://localhost:2283/api/server/ping http://localhost:32400/identity http://localhost:8096/health http://127.0.0.1:8080/"
    for t in faststore warmstore coldstore; do mount_tier "$t"; done
    for j in storage powermgmt colima compose.immich plex jellyfin landing media.watcher updatecheck snapshot mcp; do
        echo "- 0 io.homelab.$j" >>"$FAKE_LIST"
    done
}

# --- check_storage_usage.sh -------------------------------------------------------

@test "usage: an empty mount-point folder is reported, never measured (D22)" {
    mount_tier faststore
    mkdir -p "$VOL/warmstore"   # a folder, not a volume
    run bash "$USAGE"
    [[ "$output" == *"warmstore ($VOL/warmstore)"*"Not mounted"* ]] || false
    ! grep -q "df .*warmstore" "$CALLS" || false
}

@test "usage: each tier uses its own manifest thresholds" {
    mount_tier faststore; mount_tier warmstore
    FAKE_USAGE="$VOL/faststore=81 $VOL/warmstore=81" run bash "$USAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"faststore"*"WARNING (at or above 80%)"*"warmstore"*"OK (warns at 85%)"* ]] || false
}

@test "usage: critical, and exit 1" {
    mount_tier warmstore
    FAKE_USAGE="$VOL/warmstore=96" run bash "$USAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CRITICAL (at or above 95%)"* ]] || false
}

@test "usage: all below warn exits 0" {
    mount_tier faststore
    FAKE_USAGE="$VOL/faststore=34" run bash "$USAGE"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: 34%"*"within limits"* ]] || false
}

@test "usage: a threshold set by the caller wins over the manifest" {
    mount_tier faststore
    HOMELAB_TIER_FASTSTORE_WARN_PCT=30 FAKE_USAGE="$VOL/faststore=34" run bash "$USAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"WARNING (at or above 30%)"* ]] || false
}

@test "usage: no color escape codes" {
    mount_tier faststore
    run bash "$USAGE"
    [[ "$output" != *$'\033'* && "$output" != *'\033'* ]] || false
}

# --- health_check.sh ------------------------------------------------------------

@test "health: every job in the manifest is checked, jellyfin and mcp included" {
    run bash "$HEALTH"
    for j in storage powermgmt colima compose.immich plex jellyfin landing media.watcher updatecheck snapshot mcp; do
        [[ "$output" == *"io.homelab.$j - "* ]] || false
    done
}

@test "health: labels match exactly, not by prefix" {
    echo "- 0 io.homelab.compose.immich.old" >>"$FAKE_LIST"
    run bash "$HEALTH"
    [[ "$output" == *"❌ io.homelab.compose.immich - Not loaded"* ]] || false
}

@test "health: held jobs are reported as held and need no LaunchD fix" {
    all_up
    grep -vE 'colima|compose.immich|media.watcher' "$FAKE_LIST" >"$FAKE_LIST.new"; mv "$FAKE_LIST.new" "$FAKE_LIST"
    printf '\t"io.homelab.colima" => disabled\n\t"io.homelab.compose.immich" => disabled\n\t"io.homelab.media.watcher" => disabled\n' >"$FAKE_DISABLED"
    run bash "$HEALTH"
    [[ "$output" == *"io.homelab.colima - Held"* ]] || false
    [[ "$output" != *"configure_launchd.sh"* ]] || false
    [[ "$output" == *"ALL SYSTEMS OPERATIONAL"* ]] || false
}

@test "health: a job that exited non-zero is flagged" {
    echo "- 1 io.homelab.storage" >>"$FAKE_LIST"
    run bash "$HEALTH"
    [[ "$output" == *"⚠️  io.homelab.storage - Loaded, last exit 1"* ]] || false
}

@test "health: coldstore is checked where the manifest says, not /Volumes/Archive" {
    mount_tier faststore
    run bash "$HEALTH"
    [[ "$output" == *"coldstore: Not mounted - $VOL/coldstore"* ]] || false
    [[ "$output" != *"Archive"* ]] || false
}

@test "health: assessment mode changes nothing" {
    FAKE_COLIMA=0 run bash "$HEALTH"
    [[ "$output" == *"RECOVERY NEEDED"* ]] || false
    ! grep -qE "colima start|^open |kickstart" "$CALLS" || false
}

@test "health: --auto-recover starts Colima and Plex and restarts the landing job" {
    FAKE_COLIMA=0 run bash "$HEALTH" --auto-recover
    grep -q "colima start" "$CALLS"
    grep -q "open -a Plex Media Server" "$CALLS"
    grep -q "launchctl kickstart -k gui/$(id -u)/io.homelab.landing" "$CALLS"
}

@test "health: all up lists the tailnet URLs from the mappings file" {
    all_up
    run bash "$HEALTH"
    [[ "$output" == *"ALL SYSTEMS OPERATIONAL"* ]] || false
    [[ "$output" == *"landing: https://mini.example.ts.net"* ]] || false
    [[ "$output" == *"mcp: https://mini.example.ts.net:8765"* ]] || false
}
