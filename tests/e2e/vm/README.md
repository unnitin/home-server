# Sandbox kit: prove real data is untouched, rehearse deploys in a VM

Two tools for trying changes on something other than the live server.

| Tool | What it does | Status |
|---|---|---|
| `data_guard.py` | Snapshots real data and backups, and proves a later snapshot shows no change | Ready |
| VM rehearsal | Runs the Phase 0 deploy (repo move, `configure_launchd.sh`, reboot) in a disposable macOS VM | Waiting on Tart being installed |

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

## Rules for anything built on this kit

- Sandboxes get copies of data, never the real folders. Real data is read only
  to copy it out (for example, restoring a backup copy into a VM to prove the
  backup works).
- Disk and RAID commands run only inside the VM. Guest-side scripts check
  `sysctl kern.hv_vmm_present` and refuse to run on real hardware.
- A Plex copy in a sandbox never gets the real server's identity or sign-in
  token. Only the library database is restored, into a fresh, unclaimed install.
