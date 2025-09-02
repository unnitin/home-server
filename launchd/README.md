# Launchd Jobs

This folder contains macOS launchd property lists (`.plist`) to auto-start and maintain services.

## Jobs

- `io.homelab.colima.plist` → starts Colima VM (for Docker services) at boot
- `io.homelab.compose.immich.plist` → ensures Immich docker-compose stack runs on boot
- `io.homelab.updatecheck.plist` → weekly update check job (Sunday 03:30)

## Installation

Run:

```bash
sudo scripts/40_configure_launchd.sh
```

This copies plists into `/Library/LaunchDaemons`, sets permissions, and loads them with `launchctl`.

## Logs

- Colima → `/var/log/colima.{out,err}.log`
- Immich compose → `/var/log/compose-immich.{out,err}.log`
- Update check → `/var/log/homeserver-updatecheck.{out,err}.log`

Check logs with `tail -f` or open in Console.app.
