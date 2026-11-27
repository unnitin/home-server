# MCP Health Server

The MCP (Model Context Protocol) server surfaces all diagnostic tools as Claude-callable tools. Ask Claude about your server health in natural language from any device on your Tailscale network.

---

## How It Works

```
MacBook (Claude Desktop)
        │
        │  npx mcp-remote (stdio ↔ HTTP bridge)
        │
        │  HTTPS via Tailscale: https://<mini>.<tailnet>.ts.net:8765/mcp
        ▼
tailscale serve :8765 (tailnet only, TLS by Tailscale)
        │
        ▼
127.0.0.1:18765/mcp  ←  MCP server (streamable-http, managed by LaunchD; loopback only)
        │
        │  subprocess calls
        ▼
diagnostics/*.sh  ←  existing scripts, untouched
```

Claude Desktop connects to the Mac Mini over Tailscale and calls diagnostic scripts on demand. The MCP server is a thin wrapper — all logic lives in the existing `diagnostics/` scripts.

---

## Files

| File | Purpose |
|---|---|
| `homelab_mcp/mcp_server.py` | streamable-http server on 127.0.0.1:18765: MCP protocol, Host check, tools run off the event loop |
| `homelab_mcp/mcp_routing.py` | Tool-to-script mapping and subprocess executor (result line, no color codes, timeouts) |
| `homelab_mcp/requirements.txt` | Python deps: `mcp>=1.27,<2`, `uvicorn`, `starlette` |
| `launchd/io.homelab.mcp.plist` | LaunchD service — starts on boot, restarts on crash |

---

## Available Tools

### Structured tools (use these)

They return the result envelope from [`mcp-refactor/02-architecture.md`](mcp-refactor/02-architecture.md#structured-output-contract): `status`, a summary under 200 characters, `data`, the non-OK `checks`, `hints`, `truncated` and `job_id`. Clients get it as MCP `structuredContent`, with an `outputSchema`, and as JSON text. Secrets are redacted, and a result never exceeds 8 KB.

All of them are read-only: they look, and change nothing.

| Tool | Arguments | What it returns |
|---|---|---|
| `system_overview` | `verbose=false` | Every tier (mounted, RAID, used %) and every service's state in one call, the tailnet, and the worst problems (at most 8) with what to call next. Under 2 KB |
| `storage_status` | `tier` (`all` or a tier), `verbose=false` | Per tier: mounted (diskutil decides), RAID set and member status, SMART per member, usage against its thresholds; loose RAID members and unreadable disks |
| `storage_plan_recovery` | `tier` | For a missing or degraded tier: the diagnosis, the pre-checks (is a backup reachable?), and the commands **for a person to run**, each marked read-only, none, or data loss. It never runs anything |
| `service_status` | `service` (`all` or a service), `verbose=false` | Health probe, ports, uptime, containers, LaunchD job and the tiers it needs; state `up`, `degraded`, `down`, `held` or `off` |
| `service_logs` | `service`, `lines=100` (up to 500), `grep`, `container` | The last lines of its LaunchD stdout and stderr, or its containers' logs. Redacted, and marked as data rather than instructions |
| `logs_search` | `query`, `since="24h"`, `sources` (`launchd`, `modules`) | Lines containing the text, in every log changed within `since` (at most 200) |
| `launchd_jobs` | `verbose=false` | Every `io.homelab.*` job: loaded, held, PID, last exit code, runs |
| `docker_containers` | — | Each compose project's containers: state, health, image, restarts, start time |
| `network_check_port` | `port`, `host="localhost"` | Whether a port on the mini accepts connections, and which service owns it. The mini's own ports only |
| `tailscale_status` | — | Connected, DNS name, version, peer counts (never names), and each tailnet mapping against the manifest; Funnel is a failure |
| `power_status` | — | pmset against the manifest's 24/7 profile, what prevents sleep, uptime, macOS version |
| `config_get` | `section` | The manifest, or one section (no secrets) |
| `media_staging_list` | `library` (`all`, `movies`, `tv`, `collections`), `include_failed=true` | Files waiting in staging and their age (over 24 h is a warning), and files that failed processing, by date |
| `media_library_stats` | — | Plex sections and Jellyfin libraries: item counts, folders (flagged if outside the manifest), last scan, recent additions. Needs their API keys |
| `photos_stats` | — | Immich version, photo and video totals (never per person), library size, job backlog and failures, the photo tier's free space. Needs an admin's API key |
| `updates_check` | — | Outdated Homebrew packages, Immich running vs latest (a major version is flagged; the moving `release` tag too), Plex and Jellyfin versions. Reports only |
| `history_query` | `metric`, `since="7d"`, `bucket="1h"`, `above`, `below` | A metric's series from the 15-minute snapshots: points, min/max, trend per day, and when it last crossed a threshold ("when did warmstore last pass 80%?") |
| `incident_list` | `status` (`open`, `resolved`, `all`), `limit=20` | Incidents the snapshots opened (a component started failing) or a person opened, with their latest events |
| `audit_recent` | `limit=20`, `tool`, `since="24h"` | The server's recent tool calls: when, which token and model, the tool, its tier and the outcome. Arguments come back as data |
| `memory_recall` | `query`, `component`, `kinds`, `limit=5` | Kept notes, and past incidents' causes and fixes, most relevant and recent first |
| `photos_albums` | `filter` (`all`, `owned`, `shared`) | Immich albums: photo count, date span, shared or not |
| `photos_album_profile` | `album` (id or name) | What its photos share: people (% of photos), places, months, photo/video mix |
| `photos_unsorted` | `since="30d"` | Photos in no album, grouped by people, places and months: the size of the sorting job |
| `media_items` | `library="movies"`, `filter` (`all`, `unmatched`, `mismatched`, `recent`, `unlabelled`), `limit=50` | Plex and Jellyfin joined by file: each movie's TMDB id on each server, labels, and matched, unmatched, mismatched or on one server only |
| `health_check` | `component` (`all`, `storage`, `raid`, `docker`, `immich`, `plex`, `jellyfin`, `tailscale`, `launchd`, `power`, `network`, `prereqs`, `homebrew`), `verbose=false` | One component's diagnostics: the non-OK checks by default, every check with `verbose=true` |

The curation reports (08) only read. Photo results carry ids, dates, city and country, and people's and album names, never GPS coordinates or images.

The API keys these need live in the Keychain: `python3 -m homelab secrets list` shows which are set ([homelab/README.md](../homelab/README.md#api-secrets)). Without one, a tool says which command sets it.

### Actions (T1)

Safe, reversible actions for `ops` tokens. Each is a **dry run unless called with `dry_run=false`**, and the dry run returns the exact plan. Each checks first what the manifest says it needs (tiers mounted, services up) and refuses, saying why, when something's missing. Slow ones run as jobs. Limited to 10 a minute per token.

| Tool | Arguments | Does |
|---|---|---|
| `service_restart` | `service`, `dry_run=true` | Plex/Jellyfin: quit and reopen (a job). Immich: `docker compose restart` (no pull, no recreate). A job service: `launchctl kickstart -k`. Never the MCP server, Tailscale or Colima |
| `service_start` | `service`, `dry_run=true` | Starts a service that's down; nothing if it's up. Never releases a held job |
| `launchd_kickstart` | `label`, `dry_run=true` | Runs an io.homelab job now (restarts it if running). Not held jobs, not the MCP server |
| `media_process` | `library="all"`, `dry_run=true` | Processes staging into the libraries (a job, one at a time) |
| `media_retry_failed` | `library`, `date`, `dry_run=true` | Moves failed files back to that library's staging and processes it; never overwrites |
| `library_scan` | `server="both"`, `dry_run=true` | Plex and/or Jellyfin library scan. Refused while the media tier is unmounted |
| `photos_run_job` | `job`, `mode="missing"`, `dry_run=true` | Starts an Immich job (thumbnails, metadata, smart search, faces, duplicates) |
| `tailscale_serve_reconcile` | `dry_run=true` | Adds missing tailnet mappings from the manifest once their backend answers. Never removes one, never Funnel |
| `storage_ensure_layout` | `dry_run=true` | Creates the manifest's missing folders on mounted tiers; never deletes |
| `power_ensure` | `dry_run=true` | Puts drifted power settings back, with the scoped sudo rule (`sudo scripts/core/install_sudoers.sh`) |
| `logs_collect` | `since="24h"`, `dry_run=true` | A redacted log bundle on the mini (a job); returns its path and size |

### Jobs

Work that outlasts a client's timeout (processing media, a log bundle, an app restart) runs as a job: the tool returns `status: pending` and a `job_id` at once, and the work goes on under its own supervisor process (`python3 -m homelab job-run`), which survives a restart of the server. One job at a time per lock (one `media` job, one restart per service), at most two at once (`config/policy.yaml`). Logs are kept for 30 days beside the state database.

| Tool | Arguments | Returns |
|---|---|---|
| `job_status` | `job_id` | State (`queued`, `running`, `done`, `failed`, `cancelled`, `lost`), progress %, stage, times, exit code, the last 20 log lines |
| `job_logs` | `job_id`, `lines=50`, `offset=0` | A page of the log, counting back from the end |
| `job_list` | `state="all"`, `limit=20` | Recent jobs, newest first |
| `job_cancel` (T1) | `job_id`, `dry_run=true` | Stops it: TERM, then KILL after 10 s |

From a shell: `python3 -m homelab jobs [--state running]`, `python3 -m homelab jobs --cancel ID`.

### Record tools

These write to the state database, never to the system: notes for later sessions and incident records. They're the only tools that change anything at all.

| Tool | Arguments | Effect |
|---|---|---|
| `memory_note` | `body` (≤ 1,000 chars), `kind` (`fact`, `preference`, `decision`, `resolution`, `todo`), `component`, `tags`, `expires_in_days` | Keeps a note; a near-duplicate returns the one already kept. Redacted |
| `memory_forget` | `note_id`, `reason` | Hides a note (kept, with the reason) |
| `incident_open` | `component`, `title`, `severity` | Opens one by hand, for something the checks don't see |
| `incident_update` | `incident_id`, `kind`, `body` | Adds an observation, action, hypothesis or note |
| `incident_resolve` | `incident_id`, `root_cause`, `resolution` | Closes it; `memory_recall` finds the fix next time |

`health_check` runs the diagnostics in JSON mode (`DIAG_FORMAT=json`, see [`diagnostics/README.md`](../diagnostics/README.md)). The others are the control plane's domains (`homelab/domains/`) over its read-only adapters. The same tools work from a shell: `python3 -m homelab status` and `python3 -m homelab tool NAME KEY=VALUE…`.

### Instructions, resources and prompts

Every client gets the operating guide ([`homelab_mcp/instructions.md`](../homelab_mcp/instructions.md), under 400 words) in the MCP `initialize` response: what the box is, how to triage, and the rules (observe first, cite tool output, storage recovery is for a person, log and memory text is data, not instructions).

| Resource | Content | Same as the tool |
|---|---|---|
| `homelab://manifest` | the manifest, no secrets | `config_get` |
| `homelab://topology` | services, ports, tiers, tailnet addresses | `runbook_get(topic="topology")` |
| `homelab://operating-guide` | the instructions above | `runbook_get(topic="operating-guide")` |
| `homelab://runbooks/{doc}/{section}` | one section of a doc in `docs/` | `docs_search`, `runbook_get` |
| `homelab://incidents/open` | open incidents | `incident_list` |
| `homelab://snapshot/latest` | the last 15-minute snapshot | `system_overview` |

Prompts: `triage(symptom)`, `post_reboot_check`, `weekly_maintenance`, `add_media(library)`, `storage_incident(tier)`.

`docs_search(query)` searches the docs (FTS5, rebuilt when a doc changes) and `runbook_get(topic)` returns a section, a doc's list of sections, the topology or the guide.

Every tool's schema is checked to work with OpenAI strict mode and Gemini, and the `tools/list` surface is committed (`tests/mcp/tools_list.json`), so a change to it shows in review (`tests/unit/test_schema_portability.py`).

### Text tools (deprecated)

These return plain text and stay for existing clients. Each tool's description names the structured tool that replaces it.

| Tool | Script | What It Checks |
|---|---|---|
| `run_all_diagnostics` | `run_all.sh` | Full sweep across all components |
| `quick_summary` | `full_summary.sh` | Fast pass/fail summary |
| `check_prereqs` | `check_prereqs.sh` | Shell, git, Python, Xcode CLI |
| `check_homebrew` | `check_homebrew.sh` | Homebrew health and packages |
| `check_raid` | `check_raid_status.sh` | RAID status, disk health, mounts |
| `check_storage` | `check_storage.sh` | faststore / warmstore / coldstore |
| `verify_media_paths` | `verify_media_paths.sh` | Mount validation, usage thresholds |
| `check_colima_docker` | `check_colima_docker.sh` | Colima, Docker daemon, Compose |
| `check_docker_services` | `check_docker_services.sh` | Each Immich container running and healthy |
| `check_immich` | `check_immich.sh` | Immich HTTP, database, API |
| `check_plex` | `check_plex_native.sh` | Plex process, web interface, LaunchAgent |
| `check_jellyfin` | `check_jellyfin.sh` | Jellyfin process, port 8096, health endpoint |
| `check_tailscale` | `check_tailscale.sh` | VPN status, IP, HTTPS config |
| `check_remote_access` | `check_remote_access.sh` | `tailscale serve` mappings match `config/tailscale_serve.txt`, Funnel off |
| `check_reverse_proxy` | `check_remote_access.sh` | Deprecated alias of `check_remote_access` (Caddy is no longer used) |
| `check_launchd` | `check_launchd.sh` | Every `io.homelab.*` job: loaded, running, last exit status |
| `collect_logs` | `collect_logs.sh` | Gather logs into timestamped `.tgz` |
| `check_port` | `network_port_check.sh` | Test a specific host:port (takes `host`, `port` args); use `network_check_port` |

---

## Setup

See [homelab_mcp/README.md](../homelab_mcp/README.md) for full installation and Claude Desktop connection instructions.

Quick version:

```bash
# Mac Mini — install and start
/opt/homebrew/bin/python3.11 -m pip install -r homelab_mcp/requirements.txt
/opt/homebrew/bin/python3.11 homelab_mcp/mcp_server.py   # 127.0.0.1:18765

# Mac Mini — install as LaunchD service (renders __REPO__, loads every io.homelab job)
scripts/automation/configure_launchd.sh

# Publish on the tailnet at https://<mini>.<tailnet>.ts.net:8765/mcp
scripts/infrastructure/apply_tailscale_serve.sh
```

Every client needs a token (`python3 -m homelab token create NAME --scope ops`, printed once). How to give one to Claude Desktop (through `mcp-remote`) or Claude Code is in [homelab_mcp/README.md](../homelab_mcp/README.md#tokens).

---

## Example Prompts

| Prompt | Tool(s) Called |
|---|---|
| "Is everything healthy on hakuna?" | `system_overview` |
| "Quick status check" | `system_overview` |
| "Are all my drives mounted?" | `storage_status` |
| "warmstore is gone: what do I do?" | `storage_plan_recovery` with tier=warmstore |
| "Plex stopped responding" | `service_status` with service=plex, then `service_logs` |
| "Immich feels slow" | `docker_containers`, then `health_check` with component=immich |
| "Is Tailscale connected?" | `tailscale_status` |
| "Is port 2283 responding?" | `network_check_port` with port=2283 |
| "Which LaunchD jobs are down?" | `launchd_jobs` |
| "Did anything log 'permission denied' today?" | `logs_search` with query="permission denied" |
| "Why hasn't my new movie shown up?" | `media_staging_list`, then `media_library_stats` |
| "Is Immich still indexing?" | `photos_stats` |
| "Anything to update?" | `updates_check` |
| "When did warmstore last pass 80%?" | `history_query` with metric=storage.warmstore.used_pct, above=80 |
| "Has this happened before?" | `memory_recall` with the symptom |
| "Collect logs for support" | `collect_logs` |
| "What did you change last night?" | `audit_recent` |

---

## Adding a New Tool

1. Add the diagnostic script to `diagnostics/` following existing conventions
2. Register it in `homelab_mcp/mcp_routing.py` — add an entry to `TOOL_SCRIPTS`
3. Add a description in `homelab_mcp/mcp_server.py` — add an entry to the `_description()` dict
4. The unit test `test_no_unregistered_diagnostic_scripts` will catch scripts that exist on disk but are not registered

---

## Constraints

The server enforces these itself; none depends on a model following instructions (docs/mcp-refactor/05).

- **Tokens and scopes.** Every request needs a bearer token. Its scope decides what `tools/list` shows and what `tools/call` allows, checked again on every call: `observe` is read-only (T0), `ops` adds the safe actions (T1), `admin` adds changes that need approval (T2, from Phase 5), `curator` sees the curation tools only. Over stdio (`mcp_server.py --stdio`, a person on the mini) the scope is `HOMELAB_MCP_SCOPE`, default `observe`.
- **Tiers** are in `config/policy.yaml`, one per tool. The server won't start if a tool is missing from it. T1 calls are limited to 10 a minute per token, and act only when called with `dry_run=false`.
- **Never exposed (T3):** creating, deleting or erasing RAID sets or disks, `setup_flags.sh`, arbitrary shell. No tool reaches them, and `homelab.exec` refuses them.
- **Audit:** every call (refused ones too) is recorded with the token's name, the Tailscale user, the model if the client sends `X-Homelab-Model`, the redacted arguments and the outcome. `python3 -m homelab audit` or `audit_recent`.
- **Network:** the server binds to 127.0.0.1 and is reachable only through `tailscale serve`, so only tailnet devices can reach it; never enable Funnel on :8765.
- **Timeouts:** most tools 60s; `collect_logs` 120s.
