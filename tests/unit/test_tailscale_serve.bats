#!/usr/bin/env bats
# apply_tailscale_serve.sh and check_remote_access.sh against a fake `tailscale`
# (TAILSCALE_BIN) and a fake `curl` (backend up/down), so the real tailnet is never touched.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    APPLY="$ROOT/scripts/infrastructure/apply_tailscale_serve.sh"
    CHECK="$ROOT/diagnostics/check_remote_access.sh"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    export TS_CALLS="$BATS_TEST_TMPDIR/calls" TS_STATE="$BATS_TEST_TMPDIR/state.json"
    export TAILSCALE_BIN="$STUBS/tailscale" TS_NO_SUDO=1 UP_PORTS="8080 2283 32400 8096"
    : > "$TS_CALLS"

    cat > "$STUBS/tailscale" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$TS_CALLS"
case "$*" in
    "serve status --json") cat "$TS_STATE" ;;
    "status --json") echo '{"Self": {"DNSName": "mini.example.ts.net."}}' ;;
esac
exit 0
EOF
    # curl succeeds only for backends whose port is in $UP_PORTS
    cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in http://*) url="$arg" ;; esac; done
for p in $UP_PORTS; do [[ "${url:-}" == *":$p" ]] && exit 0; done
exit 7
EOF
    chmod +x "$STUBS/tailscale" "$STUBS/curl"
    export PATH="$STUBS:$PATH"

    # These tests exercise real (non-dry) applies, which is safe only because every
    # tailscale call goes to the stub above. Refuse to run otherwise. The TEST_MODE
    # test sets TEST_MODE=1 itself.
    [ -x "$TAILSCALE_BIN" ] && [ "$TAILSCALE_BIN" = "$STUBS/tailscale" ]
    export TEST_MODE=0
}

# Live state: landing, Immich and Jellyfin mapped; Plex pointing somewhere wrong;
# no MCP mapping; one mapping nobody declared.
write_state() {
    cat > "$TS_STATE" <<EOF
{"TCP": {}, "Web": {
  "mini.example.ts.net:443":   {"Handlers": {"/": {"Proxy": "http://localhost:8080"}}},
  "mini.example.ts.net:2283":  {"Handlers": {"/": {"Proxy": "http://localhost:2283"}}},
  "mini.example.ts.net:32400": {"Handlers": {"/": {"Proxy": "http://localhost:9999"}}},
  "mini.example.ts.net:8096":  {"Handlers": {"/": {"Proxy": "http://localhost:8096"}}},
  "mini.example.ts.net:9000":  {"Handlers": {"/": {"Proxy": "http://localhost:9000"}}}
}${1:-}}
EOF
}

@test "dry run reports changes and changes nothing" {
    write_state
    run bash "$APPLY" --dry-run --wait 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"plex: would repoint :32400 from http://localhost:9999"* ]] || false
    [[ "$output" == *"mcp: would map :8765 -> http://127.0.0.1:18765 (backend down"* ]] || false
    ! grep -q -- "--bg" "$TS_CALLS" || false
}

@test "TEST_MODE=1 implies dry run" {
    write_state
    TEST_MODE=1 run bash "$APPLY" --wait 0
    [ "$status" -eq 0 ]
    ! grep -q -- "--bg" "$TS_CALLS" || false
}

@test "applies missing and wrong mappings only, and never resets" {
    write_state
    UP_PORTS="8080 2283 32400 8096 18765" run bash "$APPLY" --wait 0
    [ "$status" -eq 0 ]
    grep -qx "serve --bg --https=32400 http://localhost:32400" "$TS_CALLS"
    grep -qx "serve --bg --https=8765 http://127.0.0.1:18765" "$TS_CALLS"
    [ "$(grep -c -- "--bg" "$TS_CALLS")" -eq 2 ]
    ! grep -q "reset\|off\|funnel" "$TS_CALLS" || false
}

@test "skips a mapping whose backend is down, without failing" {
    write_state
    run bash "$APPLY" --wait 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"mcp: backend http://127.0.0.1:18765 not answering, skipped"* ]] || false
    ! grep -q "https=8765" "$TS_CALLS" || false
}

@test "leaves undeclared mappings in place and reports them" {
    write_state
    run bash "$APPLY" --wait 0
    [[ "$output" == *"Undeclared mapping left in place: :9000"* ]] || false
    ! grep -q "9000" "$TS_CALLS" || false
}

@test "check_remote_access flags wrong and missing mappings" {
    write_state
    run bash "$CHECK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"OK  - Funnel off"* ]] || false
    [[ "$output" == *"OK  - landing: tailnet :443 -> http://localhost:8080"* ]] || false
    [[ "$output" == *"FAIL - plex: :32400 points at http://localhost:9999"* ]] || false
    [[ "$output" == *"WARN - mcp: not published"* ]] || false
    [[ "$output" == *"Undeclared mapping :9000"* ]] || false
}

@test "check_remote_access fails if Funnel exposes anything to the internet" {
    write_state ', "AllowFunnel": {"mini.example.ts.net:443": true}'
    run bash "$CHECK"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL - Funnel is ON"* ]] || false
}

@test "enable_landing no longer resets tailscale serve" {
    ! grep -qE "^[^#]*serve reset" "$ROOT/scripts/services/enable_landing.sh" || false
    grep -q "apply_tailscale_serve.sh" "$ROOT/scripts/services/enable_landing.sh"
}

# enable_landing.sh with a fake landing server (python3) and a fake pkill, so the
# real landing page on this machine is never touched (D28).
landing_stubs() {
    # Only the landing server is faked; the tailscale helpers parse JSON with python3.
    REAL_PYTHON3=$(PATH="${PATH#"$STUBS:"}" command -v python3)
    cat > "$STUBS/python3" <<EOS
#!/usr/bin/env bash
if [[ "\$1 \$2" == "-m http.server" ]]; then
    sleep "\${FAKE_SERVER_SECS:-1}"
    exit "\${FAKE_SERVER_RC:-0}"
fi
exec "$REAL_PYTHON3" "\$@"
EOS
    printf '#!/usr/bin/env bash\necho "$*" >> "$TS_CALLS.pkill"\nexit 1\n' > "$STUBS/pkill"
    chmod +x "$STUBS/python3" "$STUBS/pkill"
    write_state
    export TEST_MODE=1
}

@test "enable_landing --foreground stays up until the landing server exits (D28)" {
    landing_stubs
    export FAKE_SERVER_SECS=4 FAKE_SERVER_RC=3
    start=$SECONDS
    run bash "$ROOT/scripts/services/enable_landing.sh" --foreground
    [ "$status" -eq 3 ]
    [ $((SECONDS - start)) -ge 4 ]
    [[ "$output" == *"landing page server exited (3)"* ]] || false
}

@test "enable_landing without --foreground returns once the server is started" {
    landing_stubs
    export FAKE_SERVER_SECS=8
    start=$SECONDS
    # 3>&-: the background server must not hold BATS's fd 3 open
    run bash -c 'bash "$1" 3>&-' _ "$ROOT/scripts/services/enable_landing.sh"
    [ "$status" -eq 0 ]
    [ $((SECONDS - start)) -lt 8 ]
    [[ "$output" != *"Serving in the foreground"* ]] || false
}

@test "enable_landing rejects an unknown option" {
    landing_stubs
    run bash "$ROOT/scripts/services/enable_landing.sh" --bogus
    [ "$status" -eq 2 ]
}

@test "the landing LaunchD job runs enable_landing in the foreground (KeepAlive)" {
    plist="$ROOT/launchd/io.homelab.landing.plist"
    [ "$(plutil -extract KeepAlive raw -o - "$plist")" = "true" ]
    grep -q "enable_landing.sh --foreground" "$plist"
}

@test "enable_landing stops an old landing server whatever the interpreter is called" {
    landing_stubs
    run bash "$ROOT/scripts/services/enable_landing.sh" --foreground
    pattern=$(sed 's/^-f //' "$TS_CALLS.pkill")
    echo "python3 -m http.server 8080 --bind 127.0.0.1" | grep -qE "$pattern"
    echo "/Library/Frameworks/Python.app/Contents/MacOS/Python -m http.server 8080 --bind 127.0.0.1" | grep -qE "$pattern"
    ! echo "python3 -m http.server 8081" | grep -qE "$pattern" || false
}
