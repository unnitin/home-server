# 01 — Assessment of the Current Repo

## What the system does

| Function | Implemented by | How it's triggered today |
|---|---|---|
| Bootstrap & install | `setup/setup_full.sh` (interactive `read -p` prompts) | Human, once |
| RAID build / rebuild | `scripts/storage/create_*_raid.sh`, `lib/raid_common.sh` | Human, gated by `RAID_I_UNDERSTAND_DATA_LOSS=1` |
| Mount & directory layout | `storage/setup_direct_mounts.sh`, `wait_for_storage.sh` | LaunchD `io.homelab.storage` |
| Docker runtime | `infrastructure/start_docker.sh` (Colima) | LaunchD `io.homelab.colima` |
| Immich | `services/immich/docker-compose.yml`, `compose_wrapper.sh`, `deploy_containers.sh` | LaunchD `io.homelab.compose.immich` |
| Plex / Jellyfin | `start_plex_safe.sh`, `start_jellyfin_safe.sh`, `configure_*` | LaunchD, staggered `sleep 120` |
| Remote access | `configure_https.sh`, `enable_landing.sh` (`tailscale serve`) | LaunchD `io.homelab.landing` |
| Power (24/7) | `core/ensure_power_settings.sh` | LaunchD `io.homelab.powermgmt` |
| Media ingest | `media/watcher.sh` (fswatch) → `processor.sh` → `process_{movie,tv_show,collection}.sh` | LaunchD `io.homelab.media.watcher` |
| Photo import | `takeout/enhanced_takeout_import.{sh,py}` → `immich-go` | Human, can take hours |
| Updates | `automation/check_updates.sh --apply` | LaunchD `io.homelab.updatecheck` |
| Health & debugging | `diagnostics/*.sh`, `core/health_check.sh`, `collect_logs.sh` | Human, or the MCP server |
| MCP | `mcp/mcp_server.py` + `mcp_routing.py`: 16 read-only tools, 1:1 with diagnostic scripts | Claude Desktop through `mcp-remote` |

## What's good and worth keeping

- The module dependency graph (`core → storage → infrastructure → services → automation/media`) is clean and documented.
- The destructive-operation gate (`RAID_I_UNDERSTAND_DATA_LOSS`) and `TEST_MODE` give us a safety model to extend.
- `diagnostics/` is deliberately standalone, which is the right property for an agent's "eyes".
- `mcp_routing.py` is already separate from the SDK, and a drift test catches unregistered scripts.
- The uncommitted `IMMICH_VERSION` change in `docker-compose.yml` is the start of version pinning, which Phase 5 builds on.

## Defects that directly affect an MCP/agent

Verified by reading the code. Those marked ✔ were also reproduced or observed on the live system.

| # | Issue | Impact on an agent |
|---|---|---|
| D1 | `diagnostics/check_docker_services.sh` sources `compose_wrapper.sh` with no args, so it prints usage and exits 2 ✔ | The `check_docker_services` tool always returns a usage message |
| D2 | `diagnostics/run_all.sh`: a failing `run_diagnostic` call at top level trips `set -e` and the script exits before the summary ✔ (bash 3.2 repro) | `run_all_diagnostics` returns partial output exactly when something is wrong |
| D3 | `check_colima_docker.sh` calls the nonexistent `scripts/compose_helper.sh` and suggests the nonexistent `scripts/21_start_colima.sh` | Permanent false WARN, plus advice the model will repeat that leads nowhere |
| D4 | `check_launchd.sh` checks `io.homelab.immich` (the real label is `io.homelab.compose.immich`) and skips plex, jellyfin, storage, landing, media.watcher, powermgmt and mcp | Wrong answers to "which services are down?" |
| D5 | `check_reverse_proxy.sh` and `run_all.sh` probe Caddy on `:8443`, but the active setup uses `tailscale serve` (Caddy appears only in the deprecated `setup_flags.sh`) | Permanent false failures. The model chases a component that doesn't exist |
| D6 | No Jellyfin diagnostic, even though Jellyfin is a managed service on `:8096` | Blind spot |
| D7 | MCP server binds `0.0.0.0:8765` with no auth. The docs say Tailscale ACLs control access, but that only holds if the server binds to the tailnet interface | Any device on the home LAN can call tools. Not acceptable once any tool can change something |
| D8 | `launchd/io.homelab.mcp.plist` hardcodes a user home path, logs to `/tmp`, isn't templated (`__HOME__`) and isn't in `configure_launchd.sh`'s `SERVICES` | Breaks the conventions in CLAUDE.md. The server isn't installed by setup and doesn't survive a repo move |
| D9 | The tool output is `stdout+stderr` with ANSI color codes. The exit code is discarded, and `TimeoutExpired` isn't caught | Models parse escape codes, can't tell pass from fail, and get a raw exception when a tool times out |
| D10 | Path drift: `processor.sh` uses `Staging/TV Shows`, `TV Shows`, `logs/media-watcher`. `setup_direct_mounts.sh` creates `staging/tv-shows`, `tv-shows`, `logs/media-processing`. `health_check.sh` checks `/Volumes/Media` and `/Volumes/Photos`. `create_ssd_raid.sh` defaults to `/Volumes/Media` | Any tool that reports "staging has N files" is wrong for one of the two layouts |
| D11 | The `updatecheck` plist uses a `__REPO__` placeholder that `configure_launchd.sh` never fills in, so the job fails every night with "No such file or directory" ✔. Beyond that, `automation/check_updates.sh` sources `compose_wrapper.sh` (and exits with usage) and `cd`s to the nonexistent `scripts/services/immich` | The scheduled update job is broken. If it were fixed as is, it would auto-upgrade Immich to an unpinned `release` tag nightly, which is risky given Immich's breaking releases |
| D12 | CLAUDE.md tells scripts to source `scripts/core/environment.sh`, which doesn't exist | No shared config loader. Every script hardcodes its own values |
| D13 | `diag_lib.sh::run_check` uses `eval "$command"` | Injection risk once any argument comes from an LLM |
| D14 | The `mcp/` directory name shadows the `mcp` SDK package (a stale `__pycache__/server…pyc` shows an earlier collision) | Imports break depending on how the server is launched |
| D15 | `enhanced_takeout_import.py` logs to `takeout_import.log` in the current directory (there's a 9 MB copy at the repo root). The importer is synchronous and runs for hours | Can't run under a ~60 s tool-call timeout. Logs scatter |
| D16 | `setup_full.sh` and several services scripts rely on interactive prompts or `sudo` with a password | An agent can't drive them. They need non-interactive flags and a scoped sudo path |
| D17 | Several scripts edit `tailscale serve` independently. `enable_landing.sh` (LaunchD, about 150 s after login) runs `tailscale serve reset`, which wipes every mapping, then re-adds only 443, 2283 and 32400. That drops Jellyfin's 8096 mapping whenever `start_jellyfin_safe.sh` (120 s) has already added it. `configure_https.sh` points 443 at Immich, while `enable_landing.sh` points it at the landing page | Any MCP mapping added the same way would be wiped at every boot, cutting off tailnet access. What 443 serves depends on which script ran last |
| D18 | `process_movie.sh` takes the last 4-digit number in a filename as the year, so quality tags win ✔: `Dune.2021.2160p.WEB-DL.mkv` is filed as `Dune 2021 (2160)`, and `Blade.Runner.2049.2017.1080p…` as `Blade Runner 2049 2017 (1080)` | Plex and Jellyfin get the wrong year and mismatch or fail to match. Metadata work has to start with correct identification |
| D19 | 7 of the 9 loaded `io.homelab.*` jobs fail with `Operation not permitted` (exit 126) ✔. macOS privacy protection stops `/bin/bash`, launched by LaunchD, from reading scripts under `~/Documents`. The jobs are KeepAlive, so they retry forever, and one error log is over 160,000 lines. Immich, Plex and Jellyfin are up, but these jobs aren't what keeps them up, and after a reboot the boot sequence would most likely not run. The MCP job works because its Python has access | Boot-order reasoning and every LaunchD-based action assume this automation works. Fix: move the repo out of `~/Documents` (e.g. to `~/home-server`), render every plist from `__REPO__`, and check each job's last exit status |
| D20 | The Takeout importer writes Google's UTC timestamp as EXIF `DateTimeOriginal` with no time-zone offset, so a photo may show UTC as if it were local time. PNGs (and other formats piexif can't write) keep no date at all: the import counts them as errors and copies them unchanged ✔ (synthetic Takeout test) | Date-based album rules (Phase 6) and "when was this taken" answers depend on correct dates. Fix before curation: write `OffsetTimeOriginal` or local time from the GPS time zone, and set dates on PNG/HEIC/video through ExifTool or Immich's API |
| D21 | warmstore is offline ✔ (2026-11-23). Plex and Jellyfin read movies and TV from `/Volumes/warmstore/{movies,tv-shows}` (272 movies, 1,467 episodes in Plex), but it isn't mounted. Both 2 TB USB members are attached (`DISK01`, `DISK03`), yet the RAID set doesn't assemble. `DISK01` reports 4096-byte blocks where its twin reports 512, and shows only a protective MBR, which fits an enclosure or adapter presenting a different sector size from the one the disk was partitioned under. A root-owned `/Volumes/warmstore` folder sits where the volume would mount. Plex keeps the items as unavailable, and Jellyfin skips the missing folders | Nothing in the media library is reachable, so movie metadata work (Phase 6) has nothing to act on. When the set returns it may mount as `/Volumes/warmstore 1`. Fix: don't run repair or initialise on `DISK01`. Reconnect it through the enclosure or port it was set up with, confirm the set assembles, then remove the stale mount folder |
| D22 | The boot storage job is unsafe ✔ (read, not run). `setup_direct_mounts.sh` takes `-d /Volumes/warmstore` as proof it's mounted, so it would `sudo mkdir` the media folders on the internal disk. An existing but empty `movies` folder makes Plex and Jellyfin see an empty library rather than a missing one. It also runs `sudo chmod -R 755` and `chown -R` over all of `/Volumes/faststore/immich`: every original photo, and the Postgres data folder, which Postgres refuses to use unless it is 0700/0750. `wait_for_storage.sh` uses the same `-d` test. Under LaunchD, sudo can't ask for a password, so today these steps fail harmlessly. Run from a terminal with sudo cached, or with passwordless sudo, they would apply. Seen in the VM rehearsal (2026-11-23): with passwordless sudo, the job left `immich/database` at 0755; with sudo needing a password, as on the mini, all 12 sudo calls failed and nothing changed. `health_check.sh` tells you to run it with sudo | Phase 0 makes this job run again (D19), and an agent that ran the script would break Immich. Fix before deploying: test mount points with `diskutil info`, never create folders on an unmounted mount point, never chmod or chown recursively over data |
| D23 | No independent backup ✔. Original photos (113.7 GB, 59,043 files), the Immich database and its 14 nightly dumps, Plex's database and its 4 automatic backups, and Jellyfin's config all sit on one 2 TB mirror (faststore). Time Machine has no destination, the coldstore disk isn't attached, and Jellyfin has never made a backup. Checked 2026-11-23: all 14 Immich dumps decompress and end with "dump complete" (latest: 58,343 assets, 132 albums, 2,489 people), and all 8 Plex backup files pass `integrity_check` (272 movies, 1,467 episodes). The Google Takeout archives (225 GB) are a partial second copy of the photos | A mirror survives one disk failing, not deletion, corruption, a bad restore or losing the enclosure. Any tool that writes to libraries (Phase 3 on) needs a copy off this volume, and a restore test into a sandbox, first |

## What's missing for "everything through MCP"

- **Structured state:** no machine-readable status for any component.
- **Control:** no restart, start/stop, kickstart, library scan or media-reprocess tools.
- **Long-running work:** no job model for takeout imports, image pulls, media processing or log bundles.
- **Context:** topology, boot order and runbooks exist only as prose in `docs/`.
- **Memory:** nothing persists between sessions: no history, incidents or record of what was tried.
- **Policy:** no tiers, approvals, per-client identity or audit trail.
- **API integration:** Immich, Plex and Jellyfin have REST APIs that give far richer state than port probes, and none of them are used.
- **Model-agnostic harness:** the setup assumes Claude Desktop through `mcp-remote`.
- **Curation:** Immich albums come only from Takeout import folders, and nothing sorts new photos into them. Movie metadata is whatever Plex and Jellyfin match on their own from folder names the parser sometimes gets wrong (D18), and nothing checks that the two servers agree.
