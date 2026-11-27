#!/usr/bin/env bats
# LaunchD templates render to valid, fully-filled plists that point at this checkout.
# Rendering uses TEST_MODE=1 (render only) with a launchctl stub that records calls,
# so no real job is ever loaded, unloaded or restarted.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    OUT="$BATS_TEST_TMPDIR/LaunchAgents"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    export LAUNCHCTL_CALLS="$BATS_TEST_TMPDIR/launchctl_calls"
    : > "$LAUNCHCTL_CALLS"
    printf '#!/usr/bin/env bash\necho "$*" >> "$LAUNCHCTL_CALLS"\n' > "$STUBS/launchctl"
    chmod +x "$STUBS/launchctl"
}

render() {
    run env PATH="$STUBS:$PATH" TEST_MODE=1 LAUNCHD_PLIST_DIR="$OUT" \
        bash "$ROOT/scripts/automation/configure_launchd.sh"
}

@test "templates contain no user-specific paths" {
    run grep -l "/Users/" "$ROOT"/launchd/*.plist
    [ "$status" -ne 0 ]
}

@test "render-only renders every job and never calls launchctl" {
    render
    [ "$status" -eq 0 ]
    [ ! -s "$LAUNCHCTL_CALLS" ]
    for name in storage powermgmt colima compose.immich plex jellyfin landing media.watcher updatecheck snapshot mcp; do
        [ -f "$OUT/io.homelab.$name.plist" ]
    done
}

@test "rendered plists are valid with every placeholder filled" {
    render
    for plist in "$OUT"/io.homelab.*.plist; do
        plutil -lint -s "$plist"
        run grep -E "__[A-Z]+__" "$plist"
        [ "$status" -ne 0 ]
    done
}

@test "rendered plists point at this checkout, and every script they run exists" {
    render
    run grep -h -oE "$ROOT/[A-Za-z0-9_./-]+\.sh" "$OUT"/io.homelab.*.plist
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    while read -r script; do
        [ -f "$script" ] || { echo "missing: $script" >&2; return 1; }
    done <<<"$output"
}

@test "updatecheck's __REPO__ is filled in (it used to fail with exit 127)" {
    render
    run grep -c "__REPO__" "$OUT/io.homelab.updatecheck.plist"
    [ "$output" = "0" ]
    grep -q "$ROOT/scripts/automation/check_updates.sh" "$OUT/io.homelab.updatecheck.plist"
}
