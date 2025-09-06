
# Setup Scripts

- `setup.sh` – bootstrap (Command Line Tools, Homebrew, base CLI)
- `setup_full.sh` – interactive full setup (asks before destructive steps)
- `setup_flags.sh` – non-interactive, flags

Examples:
```bash
setup/setup.sh
setup/setup_full.sh
setup/setup_flags.sh --all
setup/setup_flags.sh --bootstrap --colima --immich
SSD_DISKS="disk4 disk5" RAID_I_UNDERSTAND_DATA_LOSS=1 setup/setup_flags.sh --rebuild=warmstore --format-mount
```
