# 03 — Tool Catalog

## Conventions

- **Naming:** `domain_verb`, snake_case, ≤64 chars, matching `^[a-z][a-z0-9_]*$`. This is valid for OpenAI, Gemini, Anthropic, and Ollama tool calling. No dots or slashes.
- **Params:** primitives, enums and arrays of IDs only, with optional params defaulted. Enums like `service` and `tier` are generated from `config/homelab.yaml`.
- **Mutating tools** take `dry_run: bool = true`. A model has to explicitly pass `false`, and the dry run returns exactly what would happen.
- **Descriptions** follow the pattern "what it does · when to use · what it returns" in one or two sentences. Local models depend heavily on them.
- **Annotations:** each tool sets the MCP `readOnlyHint` / `destructiveHint` / `idempotentHint` annotations. Clients that support them get better UX, and nothing relies on them, because the server enforces policy.
- **Tiers** (05-safety-and-jobs.md): **T0** observe · **T1** safe, reversible actions · **T2** changes that need approval · **T3** never exposed.
- **Toolsets:** `core` (≈12 tools, the default for small models), `ops` (core + T1), `full` (everything the token's scopes allow).

## T0 — Observe (read-only)

| Tool | Params | Returns | Backed by | Toolset |
|---|---|---|---|---|
| `system_overview` | `verbose=false` | One-call snapshot: each service up/down/degraded, each tier mounted + RAID state + usage %, open incidents, pending updates, last snapshot delta | `domains/health.py` aggregating adapters | core |
| `health_check` | `component: enum[all, storage, raid, docker, immich, plex, jellyfin, tailscale, launchd, power, network, prereqs, homebrew]`, `verbose=false` | Checks envelope | `diagnostics/*.sh` with `DIAG_FORMAT=json` | core |
| `storage_status` | `tier: enum[all, faststore, warmstore, coldstore]` | Mounted, RAID set state (Online/Degraded/Rebuilding), members + SMART status, usage, growth rate + days-until-full (from history) | `adapters/diskutil.py` (`-plist`), state DB | core |
| `service_status` | `service: enum[...]` | Process/container state, port, HTTP health, LaunchD state + last exit code, version, uptime, restarts in 24 h | `domains/services.py` | core |
| `service_logs` | `service`, `lines=100 (≤500)`, `grep?`, `since?`, `container?` | Redacted log tail from the right source (LaunchD out/err, container logs, app logs) | `domains/logs.py` | core |
| `logs_search` | `query`, `since="24h"`, `sources?: enum list` | Matching lines with source + timestamp, capped | `domains/logs.py` | ops |
| `launchd_jobs` | — | All `io.homelab.*` jobs: loaded, PID, last exit, schedule | `adapters/launchd.py` (`launchctl print gui/$UID/...`) | core |
| `docker_containers` | — | Compose project state: container, image + tag + digest, health, restarts | `docker compose ps --format json` | ops |
| `network_check_port` | `host="localhost"`, `port` | Reachability + identified service | `diagnostics/network_port_check.sh` | ops |
| `tailscale_status` | — | Online, IP, DNS name, `serve` config vs. desired (manifest), cert expiry | `tailscale status --json`, `serve status --json` | core |
| `updates_check` | — | Brew outdated, Immich pinned vs. latest release (with breaking-change flag), Plex/Jellyfin versions, macOS updates | `adapters/brew.py`, GitHub releases API, service APIs | ops |
| `media_staging_list` | `library: enum[all, movies, tv, collections]`, `include_failed=true` | Pending files, sizes, age, failed files + recorded reasons | `domains/media.py` | core |
| `media_library_stats` | — | Item counts per Plex/Jellyfin section, last scan time, recent additions | Plex/Jellyfin APIs | ops |
| `photos_stats` | — | Immich asset counts, storage usage, background job queues (thumbnails, ML, face detection) and their backlog | Immich `/api/server/statistics`, `/api/jobs` | core |
| `power_status` | — | Sleep settings vs. desired 24/7 profile, uptime, last wake reason | `pmset -g`, `diagnostics/check_power_settings.sh` | ops |
| `config_get` | `section?: enum[storage, services, media, photos, remote_access, boot_order]` | Manifest section (no secrets) | `homelab/config.py` | ops |

## T1 — Safe actions (idempotent or easily reversed; no approval; audited)

| Tool | Params | Effect | Backed by |
|---|---|---|---|
| `service_restart` | `service`, `dry_run=true` | Restart via the same path LaunchD uses: `launchctl kickstart -k` for native services, `compose restart` for containers. Checks dependencies first (e.g. refuses to restart Immich if faststore is unmounted, and says why) | `domains/services.py` → existing `start_*_safe.sh` |
| `service_start` | `service`, `dry_run=true` | Start a stopped service, honoring `depends_on` | same |
| `launchd_kickstart` | `label: enum[io.homelab.*]`, `dry_run=true` | Re-run a LaunchD job | `launchctl kickstart` |
| `media_process` | `library: enum[all, movies, tv, collections]`, `dry_run=true` | Run the processor on staging → **job** | `scripts/media/processor.sh --movies-only` etc. |
| `media_retry_failed` | `library`, `date?`, `dry_run=true` | Move failed items back to staging and reprocess → **job** | `domains/media.py` |
| `library_scan` | `server: enum[plex, jellyfin, both]`, `section?` | Trigger a library refresh | Plex `/library/sections/{id}/refresh`, Jellyfin `/Library/Refresh` |
| `photos_run_job` | `job: enum[thumbnailGeneration, metadataExtraction, smartSearch, faceDetection, duplicateDetection]`, `mode: enum[missing, all]="missing"` | Kick an Immich background job | Immich `/api/jobs/{name}` |
| `tailscale_serve_reconcile` | `dry_run=true` | Make `tailscale serve` match `remote_access.tailscale_serve`. Shows the diff when dry | `domains/network.py` (scoped sudo, see 05) |
| `storage_ensure_layout` | `dry_run=true` | Create missing directories from the manifest (never deletes) | `scripts/storage/setup_direct_mounts.sh` (refactored to read manifest) |
| `power_ensure` | `dry_run=true` | Reapply the 24/7 power profile | `scripts/core/ensure_power_settings.sh` |
| `logs_collect` | `since="24h"` | Build a redacted support bundle → **job** → path + size | `diagnostics/collect_logs.sh` (output moved to `log_root/bundles/`) |

## T2 — Changes (plan → out-of-band approval → execute)

Each T2 tool returns `status: approval_required` with a `plan_id`, a human-readable plan, a rollback plan and an expiry. Execution happens only through `plan_execute(plan_id)` after a human approves (see 05).

| Tool | Params | Plan contents | Backed by |
|---|---|---|---|
| `service_stop` | `service` | What becomes unavailable, dependents affected | `domains/services.py` |
| `updates_apply` | `target: enum[brew, immich, plex, jellyfin]`, `version?` | From→to versions, release-note highlights, breaking-change flags, backup step (Immich DB dump), rollback (previous `IMMICH_VERSION`) | `domains/updates.py`; uses `IMMICH_VERSION` pinning in `services/immich/.env` |
| `updates_rollback` | `target`, `to_version?` | Revert to the previously recorded version | state DB version history |
| `photos_import_takeout` | `source_path`, `upload=true`, `album_mode: enum[folder, none]="folder"` | File count/size estimate, disk-space check on faststore, duration estimate → **job** (hours) | `scripts/takeout/enhanced_takeout_import.sh` (made non-interactive, logs to `log_root/takeout/`) |
| `photos_backup_db` | — | `pg_dump` of the Immich DB to `coldstore` | `docker exec immich-db pg_dump` |
| `config_set` | `key` (dotted path, validated), `value` | Diff of the manifest, which services need a restart | `homelab/config.py` (writes `homelab.local.yaml` only) |
| `launchd_install` | `label`, `action: enum[install, reload, unload]` | Rendered plist diff | `scripts/automation/configure_launchd.sh` (per-service mode) |

## T3 — Never exposed

`create_*_raid`, `delete_raid*`, `format_and_mount`, `preclean_disks`, `cleanup_disks`, `rebuild_storage`, `diskutil erase*`, anything that touches `setup/setup_flags.sh`, arbitrary shell. No MCP code path can reach them. `exec.py`'s allowlist excludes them, and a test asserts it.

The same applies to curation: deleting or trashing photos (including duplicate cleanup), deleting albums, sharing albums or creating share links, naming or merging people, deleting media files or library items, and changing Plex or Jellyfin users, libraries or parental controls (08).

Instead there's a read-only planner:

| Tool | Tier | Returns |
|---|---|---|
| `storage_plan_recovery` | T0 | For a degraded or missing tier: diagnosis, whether a rebuild is needed, the exact commands with disk IDs **for a human to run**, the data-loss warning, and the pre-checks (backup status of coldstore). It never executes anything |

## Jobs, approvals, memory, context (cross-cutting)

| Tool | Tier | Purpose |
|---|---|---|
| `job_status` | T0 | `job_id` → state, progress %, started, ETA, last 20 log lines |
| `job_logs` | T0 | `job_id`, `lines`, `offset` → paged log |
| `job_list` | T0 | `state?: enum[running, queued, done, failed]` |
| `job_cancel` | T1 | `job_id` → SIGTERM, then SIGKILL after a grace period |
| `plan_status` | T0 | `plan_id` → pending/approved/rejected/expired/executed |
| `plan_execute` | T2 | `plan_id` → runs only if approved out-of-band and not expired |
| `memory_recall` | T0 | 04-context-and-memory.md |
| `memory_note` | T1 | 04 |
| `incident_list` / `incident_open` / `incident_update` / `incident_resolve` | T0/T1 | 04 |
| `history_query` | T0 | `metric: enum[...]`, `since` → time series from snapshots |
| `audit_recent` | T0 | Last N tool calls with caller, args, outcome |
| `docs_search` / `runbook_get` | T0 | Tool mirrors of MCP resources (04) |

## Curation tools (design in 08-curation.md)

"Escalates to T2" means the call is allowed as T1, but under the listed conditions the server turns it into a plan that needs approval instead of applying it (05).

### Photos (Immich)

| Tool | Tier | Params | Returns / effect | Backed by |
|---|---|---|---|---|
| `photos_albums` | T0 | `filter: enum[all, owned, shared]` | Albums with photo count, date span, whether shared, saved rule, pending review | Immich albums API |
| `photos_album_profile` | T0 | `album` | What the album's photos have in common: people (% of photos), places, date clusters, photo/video mix, saved rule | `domains/curation_photos.py` |
| `photos_find` | T0 | `query?`, `person?`, `place?`, `taken_from?`, `taken_to?`, `in_no_album=false`, `limit=50` | Compact rows: id, date, city/country, people, albums. Never GPS coordinates or pixels | Immich smart + metadata search |
| `photos_unsorted` | T0 | `since="30d"` | Photos in no album, grouped by month, place and people | Immich metadata search |
| `photos_view` | T0, `thumbnails` tokens only | `asset_id` | The thumbnail as MCP image content, for models that can see images | Immich thumbnail endpoint |
| `photos_propose` | T1 → job | `album`, `source: enum[unsorted, recent, all]="unsorted"` | Fills the album's private review album with candidates its rule finds, with evidence per photo | rules engine |
| `photos_suggest_albums` | T1 → job | `since`, `kind: enum[trips, events]` | Clusters unsorted photos by time and place into `Review: New …` albums | clustering over dates and places |
| `photos_album_add` | T1, escalates to T2 for a shared album or more than 20 photos | `album`, `asset_ids` | Adds photos directly. Recorded for undo | Immich album assets API |
| `photos_tag` | T1 | `tag`, `asset_ids` (≤200) | Adds a tag, creating it if new | Immich tags API |
| `photos_describe` | T1, `thumbnails` tokens only | `asset_id`, `text` | Fills an empty description only | Immich asset update |
| `photos_archive` | T2 | `asset_ids` | Moves photos (screenshots, receipts) out of the timeline | Immich asset update |
| `review_apply` | T2 | `review_id` | Adds what's left in the review album to the real album, records the photos you removed as "no", empties the review album | Immich album assets API |

### Movies (Plex + Jellyfin)

| Tool | Tier | Params | Returns / effect | Backed by |
|---|---|---|---|---|
| `media_items` | T0 | `library: enum[movies, tv]="movies"`, `filter: enum[all, unmatched, mismatched, recent, unlabelled]`, `limit=50` | Items joined across both servers by file path: title, year, TMDB ID per server, labels, collections, match status | Plex + Jellyfin APIs |
| `media_item` | T0 | `item` | Everything both servers know about it, plus streams (resolution, audio and subtitle languages) and play history | same |
| `media_match_candidates` | T0 | `item`, `title?`, `year?` | Candidates from both servers' own match search, merged by TMDB ID: title, year, original title, short overview | Plex Fix Match search, Jellyfin Identify search |
| `media_fix_match` | T1, escalates to T2 if the item is already matched | `item`, `tmdb_id` | Applies the match on both servers and checks they agree. `tmdb_id` must be one the server just returned as a candidate | same |
| `media_label` | T1, escalates to T2 for access labels | `items`, `label`, `kind: enum[label, collection]` | Adds a Plex label or collection and the matching Jellyfin tag or collection. Refuses an access label on items that don't meet its rules (08) | same |
| `media_unlabel` | T2, except allow-list access labels (T1: removing access is the safe direction) | `items`, `label`, `kind` | Removes them | same |
| `media_edit` | T1, escalates to T2 for content rating or overwriting a value | `item`, `field: enum[sort_title, title, year, summary, content_rating]`, `value` | Sort title on any item. Title, year and summary only on items no provider matched. Locks the field | same |
| `media_rename_to_id` | T2 | `item` | Renames the folder to carry the TMDB ID and rescans. Only for items under 24 h old that have never been played | `domains/curation_media.py` |
| `media_enrich` | T1 → job | `scope: enum[item, new_since, backfill]`, `item?`, `since?` | Checks matches, applies saved rules, turns anything uncertain into a plan | rules engine |

### Shared

| Tool | Tier | Purpose |
|---|---|---|
| `curation_rules` | T0 | Current rules for albums, tags and movie labels |
| `curation_rule_test` | T0 | `target` + rule fields (people, places, dates, search phrases; or rating and genres) → how many of the target's current items the rule finds, how many new items it would add, 10 samples |
| `curation_rule_save` | T2 | Saves a rule to `config/curation.yaml`, optionally with `auto_apply` |
| `curation_changes` | T0 | Change log with undo IDs |
| `curation_undo` | T1 | Reverts one change set |

## Tool count and toolsets

- `core` has 12 tools: `system_overview, health_check, storage_status, service_status, service_logs, launchd_jobs, tailscale_status, media_staging_list, photos_stats, memory_recall, runbook_get, job_status`
- `ops` adds 20 tools: core + the rest of T0 + T1 + jobs + incidents
- `curator` has about 28 tools: the curation tools + `memory_recall`, `job_status`, `plan_status`. The harness can narrow it to the photo half or the movie half (about 18 each)
- `full` has about 70 tools: ops + curator + T2 + `plan_*` + `config_set`

The toolset is chosen by the bearer token's scope (05). That way a local model on a small context window never sees 70 schemas, whatever client it uses.

## Migration of existing tools

The current 16 tool names stay as **deprecated aliases** for one release so existing Claude Desktop configs keep working. Each one maps to `health_check(component=…)`, and the alias's description says "Deprecated: use health_check". `tests/unit/test_mcp_routing.py` becomes a registry test that asserts every `diagnostics/check_*.sh` is reachable through `health_check`.
