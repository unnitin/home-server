#!/usr/bin/env bats
# scripts/core/install_sudoers.sh, with visudo stubbed and the target in a temp dir.

setup() {
    REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO/scripts/core/install_sudoers.sh"
    export TEST_MODE=1
    export HOMELAB_SUDOERS_FILE="$BATS_TEST_TMPDIR/sudoers.d/homelab"
    mkdir -p "$BATS_TEST_TMPDIR/sudoers.d" "$BATS_TEST_TMPDIR/bin"
    HOMELAB_PYTHON="$(command -v python3)"
    export HOMELAB_PYTHON
    # visudo stub: logs its arguments; VISUDO_FAIL=cf|c makes that check fail
    cat >"$BATS_TEST_TMPDIR/bin/visudo" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$BATS_TEST_TMPDIR/visudo.log"
[[ "${VISUDO_FAIL:-}" == "cf" && "$1" == "-cf" ]] && exit 1
[[ "${VISUDO_FAIL:-}" == "c" && "$1" == "-c" && $# -eq 1 ]] && exit 1
exit 0
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/visudo"
    export VISUDO="$BATS_TEST_TMPDIR/bin/visudo"
    export SUDO_USER=someone
}

@test "print shows exact pmset commands for the named user, no wildcards, no diskutil" {
    run "$SCRIPT" --print
    [ "$status" -eq 0 ]
    [[ "$output" == *"/usr/bin/pmset -a sleep 0"* ]]
    [[ "$output" == *"someone ALL = (root) NOPASSWD:"* ]]
    rules=$(grep -v '^#' <<<"$output")   # the comments say why diskutil is absent
    [[ "$rules" != *"*"* ]]
    [[ "$rules" != *"diskutil"* ]]
}

@test "install validates, then writes the file mode 0440" {
    run "$SCRIPT" --yes
    [ "$status" -eq 0 ]
    [ -f "$HOMELAB_SUDOERS_FILE" ]
    [ "$(stat -f %Lp "$HOMELAB_SUDOERS_FILE")" = "440" ]
    grep -q -- "-cf " "$BATS_TEST_TMPDIR/visudo.log"
    grep -qx -- "-c" "$BATS_TEST_TMPDIR/visudo.log"
}

@test "a second install finds it current and changes nothing" {
    "$SCRIPT" --yes
    run "$SCRIPT" --yes
    [ "$status" -eq 0 ]
    [[ "$output" == *"installed and current"* ]]
}

@test "a rule visudo rejects is never installed" {
    VISUDO_FAIL=cf run "$SCRIPT" --yes
    [ "$status" -eq 1 ]
    [ ! -e "$HOMELAB_SUDOERS_FILE" ]
}

@test "if the whole sudo config fails to check afterwards, the file is removed" {
    VISUDO_FAIL=c run "$SCRIPT" --yes
    [ "$status" -eq 1 ]
    [ ! -e "$HOMELAB_SUDOERS_FILE" ]
}

@test "without --yes it asks, and no means nothing is installed" {
    run bash -c "echo n | '$SCRIPT'"
    [ "$status" -eq 1 ]
    [ ! -e "$HOMELAB_SUDOERS_FILE" ]
}

@test "remove takes the file away" {
    "$SCRIPT" --yes
    run "$SCRIPT" --remove
    [ "$status" -eq 0 ]
    [ ! -e "$HOMELAB_SUDOERS_FILE" ]
}

@test "outside TEST_MODE it refuses to install without root" {
    [ "$(id -u)" -ne 0 ] || skip "running as root"
    TEST_MODE=0 run "$SCRIPT" --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"Run it with sudo"* ]]
}
