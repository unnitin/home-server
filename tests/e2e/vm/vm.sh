#!/usr/bin/env bash
# Manage disposable macOS VMs for rehearsing homelab changes.
#
#   vm.sh golden            build homelab-golden from the base image (once)
#   vm.sh up NAME           clone the golden image to NAME and boot it headless
#   vm.sh sh NAME 'CMD'     run a shell command in NAME
#   vm.sh down NAME         shut NAME down
#   vm.sh destroy NAME      delete NAME and its data disks
#   vm.sh list              list VMs
#
# VM names must start with "homelab-". Needs Tart (TART_BIN, PATH, or
# ~/Applications/tart.app). The base image is VM_BASE_IMAGE (default: macOS
# Sequoia, matching the mini). VMs live in ~/.tart, data disks in
# ~/.homelab-sandbox (HOMELAB_SANDBOX_DIR).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

GUEST_KIT=/private/var/tmp/homelab-vm

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

push_kit() {
    vm_push "$1" "$SCRIPT_DIR/guest" "$GUEST_KIT"
    tar -C "$SCRIPT_DIR" -cf - data_guard.py |
        tart_exec "$VM_EXEC_TIMEOUT" -i "$1" /usr/bin/tar -C "$GUEST_KIT" -xf -
}

cmd_golden() {
    local g="$VM_GOLDEN" app bytes
    if vm_exists "$g"; then
        log_error "$g already exists. Destroy it first: vm.sh destroy $g"
        return 1
    fi
    log_info "Cloning $VM_BASE_IMAGE to $g"
    tart_cmd clone "$VM_BASE_IMAGE" "$g"
    tart_cmd set "$g" --cpu "$VM_CPU" --memory "$VM_MEMORY_MB"
    vm_make_disks "$g"
    bytes=$(stat -f %z "$(vm_disk "$g")")

    log_info "Booting $g"
    vm_start "$g"
    vm_wait_ready "$g" 600
    vm_wait_login "$g" 300
    push_kit "$g"

    for app in "Plex Media Server" "Jellyfin"; do
        if [[ -d "/Applications/$app.app" ]]; then
            log_info "Copying $app.app (the version installed on this Mac)"
            vm_push "$g" "/Applications/$app.app" "/Applications/$app.app"
        else
            log_warn "/Applications/$app.app not found on this Mac; skipped"
        fi
    done

    log_info "Provisioning (inside the VM)"
    vm_sh "$g" "DATA_DISK_BYTES=$bytes bash $GUEST_KIT/provision_golden.sh"

    log_info "Rebooting $g to check the setup survives a restart"
    vm_stop "$g"
    vm_start "$g"
    vm_wait_ready "$g" 600
    vm_wait_login "$g" 300
    vm_sh "$g" "bash $GUEST_KIT/verify_golden.sh" || {
        log_error "$g lost part of its setup across a reboot (see above)"
        vm_stop "$g"
        return 1
    }
    vm_stop "$g"
    log_info "Golden image ready: $g"
}

cmd_up() {
    local name="${1:?usage: vm.sh up NAME}"
    vm_check_name "$name"
    vm_exists "$VM_GOLDEN" || {
        log_error "no golden image; run: vm.sh golden"
        return 1
    }
    vm_exists "$name" || vm_clone "$VM_GOLDEN" "$name"
    vm_running "$name" || vm_start "$name"
    vm_wait_ready "$name" 600
    vm_wait_login "$name" 300
    push_kit "$name"
    log_info "$name is up"
}

main() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        golden) cmd_golden ;;
        up) cmd_up "$@" ;;
        sh)
            vm_check_name "${1:?usage: vm.sh sh NAME CMD}"
            vm_sh "$@"
            ;;
        down) vm_stop "${1:?usage: vm.sh down NAME}" ;;
        destroy) vm_delete "${1:?usage: vm.sh destroy NAME}" ;;
        list) tart_cmd list ;;
        -h | --help | help | "") usage ;;
        *)
            usage
            return 2
            ;;
    esac
}

main "$@"
