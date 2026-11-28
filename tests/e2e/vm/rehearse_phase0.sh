#!/usr/bin/env bash
# Rehearse the Phase 0 deploy in a disposable macOS VM.
#
#   rehearse_phase0.sh [--ref REF] [--keep] [--no-seed] [--no-host-guard] [--out DIR]
#
# Steps, all inside a fresh clone of the golden VM (vm.sh golden):
#   1. Host guard: snapshot the real data (read-only) to prove later that the
#      rehearsal didn't touch it. Then check the clone: faststore I/O works
#      and the golden setup is intact (guest/verify_golden.sh).
#   2. Seed: copy the latest Plex backup and Jellyfin config into the VM and
#      restore them, proving the backups can seed a service.
#   3. Today's layout: the repo at REF in ~/Documents, jobs loaded with
#      configure_launchd.sh. Expect D19: bash jobs exit 126.
#   4. Deploy: move the repo to ~/home-server, run configure_launchd.sh and
#      apply_tailscale_serve.sh, as in docs/mcp-refactor/07-roadmap.md.
#   5. Reboot the VM (a clean shutdown, as you would reboot the mini), wait for
#      the boot jobs, and record every job's exit status, the diagnostics, and
#      whether MCP, Plex and Jellyfin answer.
#   6. Phase 3, when REF has tokens (homelab/auth.py): 401 without a token,
#      what observe and ops see, a real Jellyfin restart, a Plex restart job
#      that survives a restart of the MCP server, the audit log, the scoped
#      sudo rule and power_ensure, a log bundle, and D32 (guest/phase3_checks.sh).
#   7. Phase 2, when REF has the state database (homelab/state/): the snapshot
#      job ran, the MCP server serves the Phase 2 surface, and the acceptance
#      case: unmounting the VM's faststore opens an incident at the next
#      snapshot, and remounting it resolves it (guest/phase2_checks.sh).
#   7. Guards: the VM's own faststore must be unchanged by the deploy and boot,
#      and the host's real data must be unchanged.
#
# Expected in a VM: colima and compose.immich fail (macOS VMs can't run
# nested VMs, so no Docker), Tailscale steps report it isn't installed, and
# RAID diagnostics find no AppleRAID set (faststore is a plain APFS disk).
#
# Every guest command is limited to VM_EXEC_TIMEOUT seconds (default 900), so
# a wedged guest fails the run instead of hanging it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

REF=HEAD KEEP=false SEED=true HOST_GUARD=true OUT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ref) REF="$2"; shift 2 ;;
        --keep) KEEP=true; shift ;;
        --no-seed) SEED=false; shift ;;
        --no-host-guard) HOST_GUARD=false; shift ;;
        --out) OUT="$2"; shift 2 ;;
        -h | --help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) log_error "unknown option $1"; exit 2 ;;
    esac
done

RUN="homelab-rehearsal-$(date +%Y%m%d-%H%M%S)"
OUT="${OUT:-$SANDBOX_DIR/runs/$RUN}"
GUEST_KIT=/private/var/tmp/homelab-vm
GUEST_OUT=/private/var/tmp/homelab-rehearsal
BOOT_SETTLE="${BOOT_SETTLE:-240}"
PY="$(command -v python3.11 || command -v python3)"
# Inside the VM, guard what a deploy must never touch. Plex and Jellyfin
# rewrite their own (restored) data while running, so only their folder
# modes are guarded.
VFS=/Volumes/faststore
VM_GUARD="--root $VFS/immich/upload --root $VFS/immich/backups --root $VFS/immich/library \
--root $VFS/immich/profile --mode-dir $VFS/immich --mode-dir $VFS/immich/database \
--mode-dir $VFS/plex --mode-dir $VFS/jellyfin"
mkdir -p "$OUT"
exec > >(tee -a "$OUT/rehearsal.log") 2>&1

cleanup() {
    if $KEEP; then
        log_info "Keeping $RUN (vm.sh destroy $RUN when done)."
        log_warn "It holds copies of the Plex and Jellyfin data."
    else
        vm_delete "$RUN"
    fi
}

# --- 1. host guard ------------------------------------------------------
if $HOST_GUARD; then
    log_info "Host guard: snapshot of real data (read-only)"
    "$PY" -I "$SCRIPT_DIR/data_guard.py" snapshot "$OUT/host-before.json" >/dev/null
fi

log_info "Run $RUN, ref $(git -C "$REPO_ROOT" rev-parse --short "$REF"), output $OUT"
vm_exists "$VM_GOLDEN" || { log_error "no golden image; run: vm.sh golden"; exit 1; }
vm_clone "$VM_GOLDEN" "$RUN"
trap cleanup EXIT
vm_start "$RUN"
vm_wait_ready "$RUN" 600
vm_wait_login "$RUN" 300
vm_push "$RUN" "$SCRIPT_DIR/guest" "$GUEST_KIT"
tar -C "$SCRIPT_DIR" -cf - data_guard.py |
    tart_exec "$VM_EXEC_TIMEOUT" -i "$RUN" /usr/bin/tar -C "$GUEST_KIT" -xf -
tart_exec 300 "$RUN" /bin/bash "$GUEST_KIT/io_smoke.sh" || {
    log_error "faststore I/O smoke test failed in $RUN; the rehearsal would hang"
    exit 1
}
vm_sh "$RUN" "bash $GUEST_KIT/verify_golden.sh" >"$OUT/verify-golden.txt" 2>&1 || {
    cat "$OUT/verify-golden.txt"
    log_error "$RUN does not match the golden setup; rebuild it: vm.sh destroy $VM_GOLDEN && vm.sh golden"
    exit 1
}

# --- 2. seed ------------------------------------------------------------
if $SEED; then
    stage="$(vm_dir "$RUN")/seed"
    plexdb="/Volumes/faststore/plex/metadata/Plug-in Support/Databases"
    mkdir -p "$stage/plex"
    latest=$(ls -1 "$plexdb"/com.plexapp.plugins.library.db-20* 2>/dev/null | tail -1 || true)
    if [[ -n "$latest" ]]; then
        cp "$latest" "$stage/plex/com.plexapp.plugins.library.db"
        blobs="$plexdb/com.plexapp.plugins.library.blobs.db-${latest##*.db-}"
        [[ -f "$blobs" ]] && cp "$blobs" "$stage/plex/com.plexapp.plugins.library.blobs.db"
        log_info "Seed: Plex backup $(basename "$latest")"
    fi
    if [[ -d /Volumes/faststore/jellyfin/config ]]; then
        rsync -a --exclude '/cache/' --exclude '/log/' \
            /Volumes/faststore/jellyfin/config/ "$stage/jellyfin-config/"
        log_info "Seed: Jellyfin config"
    fi
    vm_push "$RUN" "$stage" /private/var/tmp/homelab-seed
    rm -rf "$stage"
    vm_sh "$RUN" "bash $GUEST_KIT/seed_services.sh /private/var/tmp/homelab-seed"
fi

# --- 3. today's layout --------------------------------------------------
log_info "Today's layout: repo in ~/Documents"
vm_sh "$RUN" 'mkdir -p ~/Documents/home-server'
git -C "$REPO_ROOT" archive --format=tar "$REF" |
    tart_exec "$VM_EXEC_TIMEOUT" -i "$RUN" /bin/bash -c 'tar -C ~/Documents/home-server -xf -'
vm_sh "$RUN" "/opt/homebrew/bin/python3.11 $GUEST_KIT/data_guard.py snapshot $GUEST_KIT/guard-before.json $VM_GUARD >/dev/null"
vm_sh "$RUN" 'cd ~/Documents/home-server && bash scripts/automation/configure_launchd.sh' \
    >"$OUT/configure-documents.txt" 2>&1 || true
log_info "Waiting ${BOOT_SETTLE}s for jobs"
sleep "$BOOT_SETTLE"
vm_sh "$RUN" "bash $GUEST_KIT/report.sh 1-documents $GUEST_OUT" >/dev/null || true

# --- 4. deploy ----------------------------------------------------------
log_info "Deploy: move repo to ~/home-server, reload jobs, apply serve config"
vm_sh "$RUN" 'mv ~/Documents/home-server ~/home-server'
vm_sh "$RUN" 'cd ~/home-server && bash scripts/automation/configure_launchd.sh' \
    >"$OUT/configure-home.txt" 2>&1 || true
vm_sh "$RUN" 'cd ~/home-server && bash scripts/infrastructure/apply_tailscale_serve.sh' \
    >"$OUT/apply-serve.txt" 2>&1 || true

# --- 5. reboot ----------------------------------------------------------
log_info "Rebooting the VM (clean shutdown)"
vm_stop "$RUN"
vm_start "$RUN"
vm_wait_ready "$RUN" 600
vm_wait_login "$RUN" 300
log_info "Waiting ${BOOT_SETTLE}s for boot jobs"
sleep "$BOOT_SETTLE"
vm_sh "$RUN" "bash $GUEST_KIT/report.sh 2-after-reboot $GUEST_OUT ~/home-server" >/dev/null || true

# --- 6. Phase 3 (before Phase 2's checks, which stop Plex and Jellyfin) ----
if git -C "$REPO_ROOT" cat-file -e "$REF:homelab/auth.py" 2>/dev/null; then
    log_info "Phase 3: tokens and scopes, real restarts, a job across a server restart, sudo rule, audit"
    vm_sh "$RUN" "VM_PASSWORD='$VM_PASSWORD' bash $GUEST_KIT/phase3_checks.sh ~/home-server $GUEST_OUT" \
        >"$OUT/phase3.txt" 2>&1 || true
fi

# --- 7. Phase 2 -----------------------------------------------------------
if git -C "$REPO_ROOT" cat-file -e "$REF:homelab/state/snapshot.py" 2>/dev/null; then
    log_info "Phase 2: snapshot job, MCP surface, unmount/remount incident"
    vm_sh "$RUN" "bash $GUEST_KIT/phase2_checks.sh ~/home-server $GUEST_OUT" \
        >"$OUT/phase2.txt" 2>&1 || true
fi

# --- 8. guards ----------------------------------------------------------
vm_sh "$RUN" "/opt/homebrew/bin/python3.11 $GUEST_KIT/data_guard.py snapshot $GUEST_KIT/guard-after.json $VM_GUARD >/dev/null"
vm_sh "$RUN" "/opt/homebrew/bin/python3.11 $GUEST_KIT/data_guard.py verify $GUEST_KIT/guard-before.json $GUEST_KIT/guard-after.json" \
    >"$OUT/vm-guard.txt" 2>&1 || true
vm_pull "$RUN" "$GUEST_OUT" "$OUT/vm"
if $HOST_GUARD; then
    "$PY" -I "$SCRIPT_DIR/data_guard.py" snapshot "$OUT/host-after.json" >/dev/null
    "$PY" -I "$SCRIPT_DIR/data_guard.py" verify "$OUT/host-before.json" "$OUT/host-after.json" \
        >"$OUT/host-guard.txt" 2>&1 || true
fi

"$PY" -I "$SCRIPT_DIR/evaluate.py" "$OUT"
