# Sandbox kit: prove real data is untouched, rehearse deploys in a VM

Two tools for trying changes on something other than the live server.

| Tool | What it does | Status |
|---|---|---|
| `data_guard.py` | Snapshots real data and backups, and proves a later snapshot shows no change | Ready |
| `vm.sh`, `rehearse_phase0.sh` | Runs the Phase 0 deploy (repo move, `configure_launchd.sh`, reboot) in a disposable macOS VM | Ready |

## data_guard.py

Run a snapshot before any sandbox, deploy or container work, and verify afterwards:

```bash
python3 tests/e2e/vm/data_guard.py snapshot ~/Library/Logs/homelab/guard-before.json
# ... do the work ...
python3 tests/e2e/vm/data_guard.py snapshot ~/Library/Logs/homelab/guard-after.json
python3 tests/e2e/vm/data_guard.py verify \
  ~/Library/Logs/homelab/guard-before.json ~/Library/Logs/homelab/guard-after.json
```

It is read-only. It records the size, modification time and permissions of
every file under the guarded folders, and the SHA-256 of every backup file. It
refuses to write its manifest inside a guarded folder. A full snapshot of the
current library (about 180,000 files, 615 GB) takes around 10 seconds, plus
hashing about 5 GB of backups.

Guarded by default (override with `--root` and `--mode-dir`; `DATA_GUARD_FASTSTORE`
moves the base path):

- Immich: `immich/upload` (originals), `library`, `profile`, `backups` (nightly
  database dumps), and any `immich-database-copy-*` folder
- Plex: the `Databases` folder, which holds the live database and its automatic backups
- Jellyfin: `config`, without `cache/` and `log/`
- Takeout: `takeout-downloads`, `tmp/takeout-processed`
- The mode and owner of `immich/`, `immich/database` (Postgres needs 0700),
  `plex/` and `jellyfin/`

`verify` sorts each difference into a bucket:

| Bucket | Examples | Exit code |
|---|---|---|
| expected | a new nightly dump, Plex's live database and WAL, a new phone upload | 0 |
| review | a dump rotated out, an original removed after the Immich trash was emptied | 0 |
| unexpected | anything else: a changed original, a rewritten backup (caught by hash), a chmod | 1 |

## VM rehearsal

Needs [Tart](https://tart.run) 2.x (`TART_BIN`, `PATH`, or `~/Applications/tart.app`).
Tart's Homebrew formula needs macOS 26 for an optional add-on. On macOS 15,
install the signed release: `tart.app` from `tart.tar.gz` on its GitHub releases page.

```bash
tests/e2e/vm/vm.sh golden                 # once: base image -> homelab-golden (~30 GB)
tests/e2e/vm/rehearse_phase0.sh           # each rehearsal: about 20 minutes
tests/e2e/vm/rehearse_phase0.sh --ref mcp-refactor --keep   # keep the VM to look around
tests/e2e/vm/vm.sh sh homelab-rehearsal-... 'launchctl list | grep homelab'
tests/e2e/vm/vm.sh destroy homelab-rehearsal-...
```

The golden image is macOS Sequoia set up to look like the mini at the storage
and service level (`guest/provision_golden.sh`):

- faststore is an APFS volume on one small virtual disk, with the real folder
  layout and permissions and a few fixture files. It is not an AppleRAID mirror
  like the mini's, because a mirror inside a macOS VM deadlocks: it accepts
  writes, then never completes the first flush, and everything touching the
  volume hangs (reproduced 2026-11-23 with and without `sync=none`; a plain
  APFS disk under the same load is fine). So RAID diagnostics can't be
  rehearsed here: `check_raid_status.sh` warns "No AppleRAID sets found".
- Plex and Jellyfin are copies of the apps installed on the mini (same
  versions), with their data folders symlinked into faststore
- `/Volumes/warmstore` is an unreadable root-owned folder with no volume behind
  it, as on the mini today (D21)
- sudo needs a password, so boot jobs fail to sudo exactly as they do on the mini
- power settings match the mini (never sleep, display sleep 1)

`vm.sh golden` reboots the new image and runs `guest/verify_golden.sh`, which
checks all of the above survived the restart; every rehearsal runs it again on
its clone before doing anything.

Two things about the mini can't be reproduced in this VM:

- **RAID** (above): faststore is a plain APFS disk.
- **D19**: the base image has System Integrity Protection turned off, so macOS
  doesn't stop launchd's bash from reading `~/Documents`, and the jobs that exit
  126 on the mini run fine in the VM. The rehearsal still runs today's layout
  and reports this as information; it can prove the deploy works after the
  move, not that the move is what fixes D19.

`rehearse_phase0.sh` clones it, restores copies of the latest Plex backup and the
Jellyfin config, and runs the deploy steps from `docs/mcp-refactor/07-roadmap.md`
in two layouts: today's (repo in `~/Documents`, which should reproduce D19) and
after the move, followed by a power cycle. `evaluate.py` then checks:

| Check | Pass when |
|---|---|
| Each `io.homelab.*` job after reboot | exit 0, never 126 or 127 |
| MCP | `initialize` on `127.0.0.1:18765` returns 200 |
| Plex, Jellyfin | answer, and the restored libraries are present |
| Immich database folder | still 0700 |
| VM faststore | `data_guard` finds no change from deploy and boot |
| Mini's real data | `data_guard` finds no change during the run |

`io.homelab.colima` and `io.homelab.compose.immich` can't pass in a VM, because
macOS VMs can't run nested VMs and so have no Docker. `io.homelab.media.watcher`
fails on the mini too while warmstore is offline (D21). These are reported, not
judged, unless they exit 126 or 127.

VMs are always shut down cleanly (`sudo shutdown` in the guest). `tart stop` on
its own presses the power button, macOS waits for a confirmation nobody gives,
and tart then cuts the power: the guest loses its last minute or so of writes.
Before this was fixed, a rehearsal's deploy and the end of a golden build both
vanished that way.

Every command sent into the VM has a time limit (`VM_EXEC_TIMEOUT`, default
900 seconds), and each rehearsal starts with `guest/io_smoke.sh`, which writes,
flushes and reads back 256 MB on faststore. A wedged guest fails the run in
minutes instead of hanging it. Output goes to `~/.homelab-sandbox/runs/<run>/`, with `result.json`
and each phase's job status, logs and diagnostics.

## Rules for anything built on this kit

- Sandboxes get copies of data, never the real folders. Real data is read only
  to copy it out (for example, restoring a backup copy into a VM to prove the
  backup works).
- Disk and RAID commands run only inside the VM. Guest-side scripts check
  `sysctl kern.hv_vmm_present` and refuse to run on real hardware. Host-side
  scripts contain no disk commands (`tests/unit/test_vm_kit.bats` checks both).
- The VM sees no host folders. Files go in and out as tar streams over `tart exec`.
- A Plex copy in a sandbox never gets the real server's identity or sign-in
  token. Only the library database is restored, into a fresh, unclaimed install.
