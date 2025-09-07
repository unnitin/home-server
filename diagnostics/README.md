
# Diagnostics Suite

These helper scripts let you quickly verify the health of your home server.

## Included scripts

- **check_raid_status.sh**  
  Shows AppleRAID sets and members.

- **check_plex_native.sh**  
  Confirms whether Plex Media Server is running natively.

- **check_docker_services.sh**  
  Runs `docker compose ps` in the Immich service folder to confirm containers are healthy.

- **network_port_check.sh <host> <port>**  
  Quickly test whether a host:port is reachable (defaults: localhost:2283).

- **collect_logs.sh**  
  Collects `/tmp/*.out` and `/tmp/*.err` logs into a timestamped tarball (e.g., `/tmp/homeserver-logs-YYYYMMDD-HHMMSS.tgz`).

- **verify_media_paths.sh**  
  Checks that `/Volumes/Media`, `/Volumes/Photos`, and `/Volumes/Archive` exist and are mounted. Prints disk usage.

## Usage examples

```bash
# RAID health
diagnostics/check_raid_status.sh

# Plex running?
diagnostics/check_plex_native.sh

# Immich containers
diagnostics/check_docker_services.sh

# Ports
diagnostics/network_port_check.sh localhost 32400  # Plex web UI
diagnostics/network_port_check.sh localhost 2283   # Immich web

# Collect logs
diagnostics/collect_logs.sh

# Check storage mountpoints
diagnostics/verify_media_paths.sh
```
