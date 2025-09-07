
Permission & Homebrew prefix fix (v2)

Applies sudo to diskutil + /Volumes mount creation and uses your Homebrew prefix
(via `brew --prefix`) for Caddy paths (works on Apple Silicon and Intel Macs).

Files updated by this patch:
- scripts/_raid_common.sh
- scripts/12_format_and_mount_raids.sh
- scripts/35_install_caddy.sh
- scripts/36_enable_reverse_proxy.sh

How to apply (from your repo root, the folder that contains 'scripts/' and 'setup/'):

  unzip ~/Downloads/permission-and-brewprefix-fix-patch-v2.zip -d .
  # Ensure executables
  bash scripts/make_executable.sh 2>/dev/null || true
  find . -type f -name "*.sh" -exec chmod +x {} \;

Re-run the flow:
  ./setup/setup_full.sh
  # or just the storage steps:
  export RAID_I_UNDERSTAND_DATA_LOSS=1 SSD_DISKS="disk4 disk5"
  scripts/10_create_raid10_ssd.sh && scripts/12_format_and_mount_raids.sh
