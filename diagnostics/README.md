# Diagnostics & Troubleshooting

This folder contains helper scripts for common issues.

> Run scripts as: `./diagnostics/<script>.sh`

## Scripts

- `check_raid_status.sh` – Summarize AppleRAID health and membership.
- `rebuild_raid_member.sh` – Replace/rebuild a failed disk (give set UUID + new disk).
- `check_docker_services.sh` – Show container status and recent logs.
- `collect_logs.sh` – Gather key logs (launchd, docker, services) into a tarball.
- `network_port_check.sh` – Verify ports for Plex and Immich are reachable.
- `verify_media_paths.sh` – Check that your media and photos paths exist & are mounted.

## Examples

```bash
# See AppleRAID
./diagnostics/check_raid_status.sh

# Replace a failed member
sudo ./diagnostics/rebuild_raid_member.sh <RAID-SET-UUID> <diskX>

# Check docker health
./diagnostics/check_docker_services.sh

# Validate open ports
./diagnostics/network_port_check.sh
```


## Run Instructions

Run any diagnostic script directly, e.g.:

```bash
./diagnostics/check_raid_status.sh
./diagnostics/check_plex_native.sh
./diagnostics/check_docker_services.sh
```

Most scripts are safe read-only checks; those that modify (like `rebuild_raid_member.sh`) require `sudo`.

