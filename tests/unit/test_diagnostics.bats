#!/usr/bin/env bats
# Diagnostics library behavior and checks that can run without live services.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
}

@test "diag_lib prints no color codes when stdout is not a terminal" {
    run bash -c 'source "$1/diagnostics/diag_lib.sh"; ok "fine"; warn "meh"; fail "bad"; true' _ "$ROOT"
    [[ "$output" != *$'\033'* ]] || false
    [[ "$output" == *"OK  - fine"* ]] || false
    [[ "$output" == *"FAIL - bad"* ]] || false
}

@test "run_check runs an argv list and never evaluates strings" {
    marker="$BATS_TEST_TMPDIR/evaluated"
    run bash -c 'source "$1/diagnostics/diag_lib.sh"; run_check "echo works" echo "\$(touch $2)"; true' _ "$ROOT" "$marker"
    [ ! -e "$marker" ]
    [[ "$output" == *"OK  - echo works"* ]] || false
}

@test "run_check records a failing command as FAIL and returns 1" {
    run bash -c 'source "$1/diagnostics/diag_lib.sh"; run_check "always fails" --show-output false || echo returned-1' _ "$ROOT"
    [[ "$output" == *"FAIL - always fails"* ]] || false
    [[ "$output" == *"returned-1"* ]] || false
}

@test "check_launchd reports exec failures (126, 127) and unloaded jobs" {
    cat > "$STUBS/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'PID\tStatus\tLabel\n'
printf -- '-\t126\tio.homelab.plex\n'
printf -- '-\t127\tio.homelab.updatecheck\n'
printf '1348\t0\tio.homelab.mcp\n'
printf -- '-\t0\tio.homelab.powermgmt\n'
EOF
    chmod +x "$STUBS/launchctl"
    run env PATH="$STUBS:$PATH" bash "$ROOT/diagnostics/check_launchd.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL - io.homelab.plex: last exit 126"* ]] || false
    [[ "$output" == *"FAIL - io.homelab.updatecheck: last exit 127"* ]] || false
    [[ "$output" == *"OK  - io.homelab.mcp: running (pid 1348)"* ]] || false
    [[ "$output" == *"OK  - io.homelab.powermgmt: idle, last exit 0"* ]] || false
    [[ "$output" == *"WARN - Not loaded: io.homelab.colima"* ]] || false
}

@test "check_launchd covers every plist in launchd/" {
    printf '#!/usr/bin/env bash\nprintf "PID\\tStatus\\tLabel\\n"\n' > "$STUBS/launchctl"
    chmod +x "$STUBS/launchctl"
    run env PATH="$STUBS:$PATH" bash "$ROOT/diagnostics/check_launchd.sh"
    for plist in "$ROOT"/launchd/io.homelab.*.plist; do
        label=$(basename "$plist" .plist)
        [[ "$output" == *"Not loaded: $label"* ]] || false
    done
}

@test "run_all records a failing check instead of aborting the sweep" {
    printf '#!/usr/bin/env bash\nexit 1\n' > "$STUBS/fails.sh"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$STUBS/passes.sh"
    chmod +x "$STUBS/fails.sh" "$STUBS/passes.sh"
    run bash -c 'eval "$(sed -n "/^run_diagnostic()/,/^}/p" "$1/diagnostics/run_all.sh")"
        SCRIPT_DIR="$2"; SCRIPT_RESULTS=(); YELLOW=""; NC=""
        warn() { echo "WARN - $*"; }
        diag_record() { :; }
        set -e
        run_diagnostic "fails.sh" "A failing check"
        run_diagnostic "passes.sh" "A passing check"
        printf "%s\n" "${SCRIPT_RESULTS[@]}"' _ "$ROOT" "$STUBS"
    [ "$status" -eq 0 ]
    [[ "$output" == *"❌ A failing check"* ]] || false
    [[ "$output" == *"✅ A passing check"* ]] || false
}
