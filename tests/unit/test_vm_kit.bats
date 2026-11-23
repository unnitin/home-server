#!/usr/bin/env bats
# Safety rules of the VM sandbox kit (tests/e2e/vm/), checked without a VM:
# guest scripts refuse to run on real hardware, host scripts never run disk
# commands, and VM deletion can't reach outside the sandbox folder.
# Note: `[[ ]] || false` because bash 3.2 doesn't fail a test on a mid-test [[ ]].

setup() {
    ROOT="$BATS_TEST_DIRNAME/../.."
    KIT="$ROOT/tests/e2e/vm"
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    export CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    # Every command a guest script could use to change the system records the
    # call and does nothing.
    for c in brew diskutil sudo pmset rsync; do
        printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\n' "$c" >"$STUBS/$c"
        chmod +x "$STUBS/$c"
    done
    export PATH="$STUBS:$PATH" TEST_MODE=1 RAID_I_UNDERSTAND_DATA_LOSS=0
}

fake_sysctl() {
    printf '#!/usr/bin/env bash\necho %s\n' "$1" >"$STUBS/sysctl"
    chmod +x "$STUBS/sysctl"
}

@test "assert_vm refuses on real hardware and allows a VM" {
    fake_sysctl 0
    run bash "$KIT/guest/assert_vm.sh"
    [ "$status" -eq 3 ]
    [[ "$output" == *"not a virtual machine"* ]] || false
    fake_sysctl 1
    run bash "$KIT/guest/assert_vm.sh"
    [ "$status" -eq 0 ]
}

@test "assert_vm refuses on this Mac (real sysctl)" {
    [ "$(sysctl -n kern.hv_vmm_present)" = 0 ] || skip "running inside a VM"
    run bash "$KIT/guest/assert_vm.sh"
    [ "$status" -eq 3 ]
}

@test "every guest script sources assert_vm.sh before doing anything" {
    for f in "$KIT"/guest/*.sh; do
        [ "$(basename "$f")" = assert_vm.sh ] && continue
        first=$(grep -nE '^[^#[:space:]]' "$f" | grep -v -E '^[0-9]+:(set |HERE=)' | head -1)
        [[ "$first" == *'source "$HERE/assert_vm.sh"'* ]] || {
            echo "$f: first action is not the VM check: $first"
            false
        }
    done
}

@test "guest scripts stop before any system change when not in a VM" {
    fake_sysctl 0
    for f in provision_golden.sh seed_services.sh report.sh io_smoke.sh verify_golden.sh; do
        DATA_DISK_BYTES=1 run bash "$KIT/guest/$f" phase "$BATS_TEST_TMPDIR/out"
        [ "$status" -eq 3 ] || { echo "$f exited $status"; false; }
    done
    [ ! -s "$CALLS" ] || { cat "$CALLS"; false; }
}

@test "host-side scripts run no disk or RAID commands" {
    for f in "$KIT/lib.sh" "$KIT/vm.sh" "$KIT/rehearse_phase0.sh"; do
        ! grep -nE '^[^#]*\b(diskutil|newfs|gpt|asr|fdisk|hdiutil|dd)\b' "$f" || false
    done
}

@test "VM names must start with homelab-" {
    source "$KIT/lib.sh"
    vm_check_name homelab-rehearsal-20261123-101500
    for bad in golden homelab- "homelab-x/../../etc" "../homelab-x" "homelab-UPPER"; do
        run vm_check_name "$bad"
        [ "$status" -eq 2 ] || { echo "accepted $bad"; false; }
    done
}

@test "vm_delete only removes the VM's own sandbox folder" {
    export HOMELAB_SANDBOX_DIR="$BATS_TEST_TMPDIR/sandbox"
    printf '#!/usr/bin/env bash\necho "tart $*" >> "$CALLS"\n' >"$STUBS/tart"
    chmod +x "$STUBS/tart"
    export TART_BIN="$STUBS/tart"
    source "$KIT/lib.sh"
    mkdir -p "$SANDBOX_DIR/homelab-a" "$SANDBOX_DIR/homelab-b"
    touch "$SANDBOX_DIR/homelab-a/faststore.img" "$SANDBOX_DIR/keep.txt"
    vm_delete homelab-a
    [ ! -e "$SANDBOX_DIR/homelab-a" ]
    [ -d "$SANDBOX_DIR/homelab-b" ]
    [ -f "$SANDBOX_DIR/keep.txt" ]
    grep -q "tart delete homelab-a" "$CALLS"
    run vm_delete ".."
    [ "$status" -eq 2 ]
    [ -d "$SANDBOX_DIR" ]
}

@test "vm_clone copies the faststore disk next to the clone" {
    export HOMELAB_SANDBOX_DIR="$BATS_TEST_TMPDIR/sandbox" VM_DATA_DISK_SIZE=1m
    printf '#!/usr/bin/env bash\necho "tart $*" >> "$CALLS"\n' >"$STUBS/tart"
    chmod +x "$STUBS/tart"
    export TART_BIN="$STUBS/tart"
    source "$KIT/lib.sh"
    vm_make_disks homelab-golden
    echo marker >"$SANDBOX_DIR/homelab-golden/faststore.img"
    vm_clone homelab-golden homelab-run-1
    grep -q "tart clone homelab-golden homelab-run-1" "$CALLS"
    [ "$(cat "$SANDBOX_DIR/homelab-run-1/faststore.img")" = marker ]
}

@test "a guest command that hangs is killed at its time limit" {
    printf '#!/usr/bin/env bash\nexec sleep 30\n' >"$STUBS/tart"
    chmod +x "$STUBS/tart"
    export TART_BIN="$STUBS/tart"
    source "$KIT/lib.sh"
    SECONDS=0
    run tart_exec 1 homelab-x /bin/true
    [ "$status" -eq 142 ]
    [ "$SECONDS" -lt 10 ]
    [[ "$output" == *"timed out after 1s"* ]] || false
}
