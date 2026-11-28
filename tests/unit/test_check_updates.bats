#!/usr/bin/env bats
# check_updates.sh reports only: it must never upgrade, pull or restart anything.
# brew, curl and docker are stubs that record their calls.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    SCRIPT="$ROOT/scripts/automation/check_updates.sh"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    export CALLS="$BATS_TEST_TMPDIR/calls"
    : > "$CALLS"
    cat > "$STUBS/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >> "$CALLS"
[[ "$1" == "outdated" ]] && printf 'colima (0.8.4) < 0.10.3\ndocker (28.4.0) < 29.10.0\n'
exit 0
EOF
    cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >> "$CALLS"
case "$*" in
    *api/server/version*) echo '{"major":2,"minor":1,"patch":0}' ;;
    *api.github.com*) echo '{"tag_name":"v3.4.2"}' ;;
esac
EOF
    printf '#!/usr/bin/env bash\necho "docker $*" >> "$CALLS"\n' > "$STUBS/docker"
    chmod +x "$STUBS"/*
}

run_check() {
    run env PATH="$STUBS:/usr/bin:/bin" bash "$SCRIPT" "$@"
}

@test "reports outdated Homebrew packages and the Immich version gap" {
    run_check
    [ "$status" -eq 0 ]
    [[ "$output" == *"Homebrew: 2 outdated"* ]] || false
    [[ "$output" == *"colima (0.8.4) < 0.10.3"* ]] || false
    [[ "$output" == *"Immich: v2.1.0 running, v3.4.2 available"* ]] || false
    [[ "$output" == *"Nothing was changed"* ]] || false
}

@test "never upgrades, refreshes metadata, pulls images or restarts containers" {
    run_check
    [ "$status" -eq 0 ]
    ! grep -qE "brew (upgrade|update|install)" "$CALLS" || false
    ! grep -q "^docker" "$CALLS" || false
}

@test "--apply is refused" {
    run env PATH="$STUBS:/usr/bin:/bin" bash "$SCRIPT" --apply
    [ "$status" -eq 2 ]
    [[ "$output" == *"--apply is disabled"* ]] || false
    [ ! -s "$CALLS" ]
}

@test "the nightly LaunchD job no longer passes --apply" {
    ! grep -q -- "--apply" "$ROOT/launchd/io.homelab.updatecheck.plist" || false
}
