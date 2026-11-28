#!/usr/bin/env bash
# Host-side helpers for the macOS VM sandbox. Sourced by vm.sh and
# rehearse_phase0.sh; not meant to be run directly.
#
# Nothing here runs a disk or RAID command on the host. Those run inside the
# guest through guest/*.sh, which refuse to run on real hardware. The guest
# sees no host folders: files go in and out as tar streams over `tart exec`.

VM_BASE_IMAGE="${VM_BASE_IMAGE:-ghcr.io/cirruslabs/macos-sequoia-base:latest}"
VM_GOLDEN="${VM_GOLDEN:-homelab-golden}"
VM_CPU="${VM_CPU:-4}"
VM_MEMORY_MB="${VM_MEMORY_MB:-4096}"
VM_DATA_DISK_SIZE="${VM_DATA_DISK_SIZE:-8g}"
# Upper bound on any one command run in the guest. A wedged guest then fails
# the run instead of hanging it.
VM_EXEC_TIMEOUT="${VM_EXEC_TIMEOUT:-900}"
SANDBOX_DIR="${HOMELAB_SANDBOX_DIR:-$HOME/.homelab-sandbox}"
VM_KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$VM_KIT_DIR/../../.." && pwd)"
export REPO_ROOT # used by rehearse_phase0.sh
VM_NAME_RE='^homelab-[a-z0-9-]+$'
# The base image's built-in account password (public: admin/admin). Only ever
# sent to a sandbox VM.
VM_PASSWORD="${VM_PASSWORD:-admin}"

log_info()  { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()  { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error() { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }

tart_bin() {
    local c
    for c in "${TART_BIN:-}" "$(command -v tart 2>/dev/null || true)" \
        "$HOME/Applications/tart.app/Contents/MacOS/tart" \
        "/Applications/tart.app/Contents/MacOS/tart"; do
        if [[ -n "$c" && -x "$c" ]]; then
            echo "$c"
            return 0
        fi
    done
    return 1
}

tart_cmd() {
    local bin
    bin="$(tart_bin)" || {
        log_error "tart not found. Install it, or set TART_BIN"
        return 127
    }
    "$bin" "$@"
}

vm_check_name() {
    if [[ ! "$1" =~ $VM_NAME_RE ]]; then
        log_error "VM name '$1' must match $VM_NAME_RE"
        return 2
    fi
}

vm_dir() { echo "$SANDBOX_DIR/$1"; }
# The guest's faststore disk. One plain APFS disk, not an AppleRAID mirror:
# a mirror deadlocks inside a macOS VM under write load (see README).
vm_disk() { echo "$(vm_dir "$1")/faststore.img"; }

# Run a command, killing it after SECS seconds (macOS has no timeout(1)).
# Exit status 142 means it timed out.
with_timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

# tart exec with a time limit: tart_exec SECS ARGS...
tart_exec() {
    local secs="$1" bin rc=0
    shift
    bin="$(tart_bin)" || {
        log_error "tart not found. Install it, or set TART_BIN"
        return 127
    }
    with_timeout "$secs" "$bin" exec "$@" || rc=$?
    ((rc == 142)) && log_error "guest command timed out after ${secs}s: ${*: -1}"
    return "$rc"
}

vm_exists() { tart_cmd get "$1" >/dev/null 2>&1; }

vm_running() {
    tart_cmd list --format json 2>/dev/null |
        python3 -c 'import json,sys; n=sys.argv[1]
sys.exit(0 if any(v.get("Name")==n and v.get("State")=="running"
    for v in json.load(sys.stdin)) else 1)' "$1"
}

# A blank, sparse disk for the guest's faststore.
vm_make_disks() {
    local name="$1" d
    mkdir -p "$(vm_dir "$name")"
    d="$(vm_disk "$name")"
    [[ -f "$d" ]] || mkfile -n "$VM_DATA_DISK_SIZE" "$d"
}

# Clone a VM and its faststore disk (APFS copy-on-write, so near-instant).
vm_clone() {
    local src="$1" dst="$2"
    vm_check_name "$dst" || return 2
    tart_cmd clone "$src" "$dst" || return 1
    mkdir -p "$(vm_dir "$dst")"
    cp -c "$(vm_disk "$src")" "$(vm_disk "$dst")" 2>/dev/null ||
        cp "$(vm_disk "$src")" "$(vm_disk "$dst")"
}

vm_start() {
    local name="$1" args=() d
    d="$(vm_disk "$name")"
    [[ -f "$d" ]] && args+=(--disk "$d")
    mkdir -p "$(vm_dir "$name")"
    nohup "$(tart_bin)" run "$name" --no-graphics "${args[@]}" \
        >"$(vm_dir "$name")/run.log" 2>&1 </dev/null &
    echo $! >"$(vm_dir "$name")/run.pid"
}

vm_exec() {
    local name="$1"
    shift
    tart_exec "$VM_EXEC_TIMEOUT" "$name" "$@"
}

# Run a bash snippet in the guest as a login shell (Homebrew on PATH).
vm_sh() {
    local name="$1"
    shift
    tart_exec "$VM_EXEC_TIMEOUT" "$name" /bin/bash -lc "$*"
}

vm_wait_ready() {
    local name="$1" timeout="${2:-300}" waited=0
    until tart_exec 30 "$name" /usr/bin/true >/dev/null 2>&1; do
        if ((waited >= timeout)); then
            log_error "$name not reachable after ${timeout}s"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

# Wait until the guest's GUI login session is up, so LaunchAgents can load.
vm_wait_login() {
    local name="$1" timeout="${2:-300}" waited=0
    until tart_exec 30 "$name" /bin/bash -lc 'launchctl print gui/$(id -u) >/dev/null 2>&1'; do
        if ((waited >= timeout)); then
            log_error "$name has no GUI session after ${timeout}s"
            return 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

# Shut the guest down cleanly, so its last writes reach its disks. `tart stop`
# alone presses the power button; macOS asks for confirmation, nobody answers,
# and tart then cuts the power, losing the last minute or so of writes (found
# 2026-11-23: a deploy and the end of a golden build vanished that way).
vm_stop() {
    local name="$1" waited=0
    if vm_running "$name"; then
        printf '%s\n' "$VM_PASSWORD" |
            tart_exec 30 -i "$name" /usr/bin/sudo -S -p '' /sbin/shutdown -h now \
                >/dev/null 2>&1 || true
        while vm_running "$name" && ((waited < 180)); do
            sleep 3
            waited=$((waited + 3))
        done
        vm_running "$name" && log_warn "$name did not shut down cleanly; forcing it off"
    fi
    tart_cmd stop "$name" --timeout 30 >/dev/null 2>&1 || true
}

# Copy a host directory's contents into the guest.
vm_push() {
    local name="$1" src="$2" dest="$3"
    tar -C "$src" -cf - . |
        tart_exec "$VM_EXEC_TIMEOUT" -i "$name" /bin/bash -c \
            "mkdir -p \"$dest\" && tar -C \"$dest\" -xf -"
}

# Copy a guest directory's contents to the host.
vm_pull() {
    local name="$1" src="$2" dest="$3"
    mkdir -p "$dest"
    tart_exec "$VM_EXEC_TIMEOUT" "$name" /bin/bash -c "tar -C \"$src\" -cf - ." |
        tar -C "$dest" -xf -
}

vm_delete() {
    local name="$1"
    vm_check_name "$name" || return 2
    vm_stop "$name"
    tart_cmd delete "$name" >/dev/null 2>&1 || true
    case "$(vm_dir "$name")" in
        "$SANDBOX_DIR"/homelab-*) rm -rf "$(vm_dir "$name")" ;;
    esac
}
