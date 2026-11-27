# 07 — Phased Roadmap

Each phase ships on its own, keeps every existing LaunchD job working, and ends with green `bats tests/unit/` + `pytest tests/`. Phases 0–2 add no mutating tools, so the current "read-only" guarantee holds until Phase 3 brings in the policy layer.

---

## Phase 0 — Foundations and bug fixes (small, do first)

| Task | Fixes |
|---|---|
| Bind MCP to `127.0.0.1:18765` and publish it on the tailnet with `tailscale serve --bg --https=8765` (Serve, not Funnel). Drop in-process cert loading. Update `tests/mcp_smoke_test.sh`, `mcp/README.md` and `docs/MCP.md` to the new URL | D7 |
| Stop serve mappings being wiped. Remove `tailscale serve reset` from `enable_landing.sh`. Add `scripts/infrastructure/apply_tailscale_serve.sh`, which adds any missing mapping (443 landing, 2283 Immich, 32400 Plex, 8096 Jellyfin, 8765 MCP) without touching the others, and adds an app's mapping only once that app answers. The landing LaunchD job runs it, and `configure_https.sh` calls it instead of setting 443 itself. The list moves into the manifest in Phase 1 | D17 |
| Template `io.homelab.mcp.plist` (`__REPO__`, Homebrew PATH, logs → `/tmp/homelab-mcp.{out,err}` like the other jobs, since warmstore may not be mounted yet at login, see #17), add `mcp` to `configure_launchd.sh` `SERVICES` | D8 |
| Rename `mcp/` → `homelab_mcp/`, delete stale `__pycache__` | D14 |
| `check_docker_services.sh`: call `docker compose -p immich ps` directly (standalone, no `scripts/` source) | D1 |
| `run_all.sh`: `run_diagnostic … \|\| true`; always print summary | D2 |
| `check_colima_docker.sh`: real compose check, correct hint (`scripts/infrastructure/start_docker.sh`) | D3 |
| `check_launchd.sh`: derive label list from `launchd/io.homelab.*.plist` filenames | D4 |
| Retire Caddy checks (`check_reverse_proxy.sh` → `check_remote_access.sh` checking `tailscale serve` state); update `run_all.sh` ports | D5 |
| Add `diagnostics/check_jellyfin.sh` | D6 |
| `mcp_routing.run`: return exit code, catch `TimeoutExpired`, strip ANSI, set `NO_COLOR=1` | D9 |
| `check_updates.sh`: remove broken source/path; **make it check-only** (drop `--apply` from the plist) until Phase 5 pinning exists | D11 |
| Replace `eval` in `diag_lib.sh::run_check` with `"$@"` argv form | D13 |
| Takeout importer: `--log-file` defaulting to `log_root/takeout/`, no CWD log | D15 |
| Make the repo location-independent: every plist uses `__REPO__` (which `configure_launchd.sh` fills in, along with `__HOME__`), `configure_launchd.sh` gets a TEST_MODE render-only path, and `check_launchd.sh` reports each job's last exit status. Moving the repo out of `~/Documents` is a deploy step | D19, D11 |
| Fix movie year parsing in `process_movie.sh`: accept only 1900–2099, take the last such number, and add BATS tests with common release names (`1080p`, `2160p`, *Blade Runner 2049*) | D18 |

**Acceptance:**
- From a tailnet device such as the MacBook, `https://<mini>.<tailnet>.ts.net:8765/mcp` answers an MCP `initialize`, and Claude Desktop connects with the updated URL.
- The same check still passes after rebooting the mini, with all five serve mappings present.
- Connections from a LAN IP to the mini's ports 8765 and 18765 fail.
- `run_all.sh` completes with a summary on a box with failures.
- All 16 existing tools return meaningful output, and the smoke test passes.

**Before deploying** (found 2026-11-23):
- Fix the boot storage job (D22). Phase 0 re-enables it, so it is a blocker.
  **Done** in `feature/d22-safe-storage` (2026-11-23). The rehearsal passed again on it (0393e19), and running the storage script as root through sudo in the VM changed no mode or owner under `immich/` or `plex/`. The Immich job now waits for faststore only.
- Rehearse the deploy in a disposable macOS VM (`tests/e2e/vm/`): repo move, `configure_launchd.sh`, a reboot, and every job's exit status.
  Done 2026-11-23 on `mcp-refactor` at cd65742: **PASS**. After the move and a clean reboot:
  - Every plist points at `~/home-server`, and every job exits 0. The exceptions are `colima` and `compose.immich` (no Docker in a VM) and the media watcher (D21).
  - MCP answers `initialize`, and Plex and Jellyfin are up.
  - Copies of the latest Plex backup and the Jellyfin config restore and load (272 movies; 14 series, setup done).
  - The Immich database folder stays 0700, and the real data is unchanged.
  - This passes only because sudo needs a password: the storage job's 12 sudo calls per boot fail. With working sudo, the same job left the database folder at 0755 (D22).
  - The Plex job's `sudo tailscale serve` calls also fail. That's harmless, because step 3 below sets the mappings without sudo.
  - The VM can't cover AppleRAID, Docker/Immich or Tailscale, and it can't reproduce D19 itself (SIP is off in the base image). See `tests/e2e/vm/README.md`.
- Take a `tests/e2e/vm/data_guard.py snapshot` before the deploy and `verify` against a second snapshot afterwards. It proves no photo, backup or database folder changed.
- warmstore (D21) can be fixed before or after. Until it's back, the media watcher and the Plex and Jellyfin libraries have nothing to read.

**Deploying Phase 0** is your call, after `mcp-refactor` is merged to `main`. Merging changes nothing on the running system.
1. Move the repo out of `~/Documents`, e.g. `mv ~/Documents/home-server ~/home-server` (D19).
2. Run `scripts/automation/configure_launchd.sh` to re-render and reload every job from the new path, `io.homelab.mcp` included.
3. Run `scripts/infrastructure/apply_tailscale_serve.sh` to add the MCP mapping and repair the others.
4. Point the Claude Desktop entry at `https://<mini>.<tailnet>.ts.net:8765/mcp`.
5. Run `bash diagnostics/run_all.sh`, and check that every job in `launchctl list | grep io.homelab` shows exit status 0.

**Deployed 2026-11-26** from `mcp-refactor` at `4ba19a6`, the same tree as the rehearsed `e9c2c66`, then the D28 fixes (#29, #30). The deployed commit is tagged `deploy-2026-11-26`, and the mini's checkout sits on a local `deployed` branch, so merges into `mcp-refactor` change nothing there until the next deploy. `mcp-refactor` stays the integration branch; draft #28 merges it into `main` when you decide.
- The repo is at `~/home-server`. Every plist is rendered from there, and none names `~/Documents`.
- Loaded: `mcp`, `storage`, `powermgmt`, `plex`, `jellyfin`, `landing`, `updatecheck`.
- Held with `launchctl disable`, which survives reboots: `colima` and `compose.immich` (Immich already runs from a manual start, and container work waits for its own phase), and `media.watcher` (D21, D26). To release one: `launchctl enable gui/$(id -u)/io.homelab.<job>`, then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.homelab.<job>.plist`.
- MCP: `https://<mini>.<tailnet>.ts.net:8765/mcp` answers the MCP client over the tailnet. From the LAN, ports 8765 and 18765 refuse connections. All five serve mappings are tailnet only, and Funnel is off.
- `run_all.sh`: 11 passed, 3 failed, all known: mounts (D21, coldstore not attached), LaunchD (the storage job exits 1, D27), power (D24, fixed in Phase 1).
- `data_guard.py verify`: no unexpected changes. The only changes are Jellyfin's live database journal files.
- Found: D26, D27, D28.
- Still to do: the reboot check from the acceptance list, and pointing MCP clients at the new URL.

## Phase 1 — Manifest and structured output

- Add `config/homelab.yaml`, `homelab/config.py` (pydantic validation) and `homelab config render-env` → `config/homelab.env`.
- Create `scripts/core/environment.sh` (D12). Migrate scripts to it in module order (`core` → `storage` → … → `media`), one PR per module. Resolve D10 path drift to the single manifest layout. Check the actual on-disk layout before choosing, and add a one-time `storage_ensure_layout` migration note.
- `diag_lib.sh` JSON mode (`DIAG_FORMAT=json`).
- MCP: the result envelope with `structuredContent` + `outputSchema`, `system_overview`, `health_check(component)`, and the 16 old tools as deprecated aliases.
- Doc hygiene pass: remove Caddy, `/Volumes/Media`, `scripts/NN_*` references. Add a test that every script path referenced in `docs/` exists.
- Update CLAUDE.md with the new modules in the dependency graph, Python conventions extended to `homelab/`, `homelab_mcp/` and `agent/`, and the manifest-first rule ("never hardcode a port, path or label; read the manifest").

**Progress** (2026-11-24):
- Built: the diagnostics JSON mode (`feature/p1-diag-json`), which also fixed D24.
- Built: `system_overview`, `health_check(component)` and the result envelope, with the old tools kept as deprecated text tools (`feature/p1-mcp-envelope`).
- Built: the doc hygiene pass (`feature/p1-doc-hygiene`). It retired Caddy, `/Volumes/Media`, `/Volumes/Photos` and the numbered script names, added a test that every script path in the docs exists, and fixed D25. Three calls in code to numbered scripts that no longer exist (`health_check.sh --auto-recover`, `ensure_power_settings.sh`) now print the command or restart the LaunchD job, and a test keeps numbered names out of code.
- Built: the manifest (`feature/p1-manifest`). `config/homelab.yaml` with the decided names (kebab-case media folders, coldstore at `/Volumes/coldstore`), `homelab/config.py` (pydantic, strict), `python3 -m homelab config validate|render|get`, and one `pyproject.toml` at the repo root. `config/homelab.env` and `config/tailscale_serve.txt` are generated from it and committed; a test fails while they're stale, and another checks the manifest against the LaunchD templates and `configure_launchd.sh`.
- Built: `scripts/core/environment.sh` (with the manifest), and `core/` moved onto it (`feature/p1-core`). `health_check.sh` now checks every job in the manifest by exact label (its own list had lost jellyfin, powermgmt, the media watcher and mcp), reports held jobs as held, and checks each service's health URL. `check_storage_usage.sh` covers every tier with its own thresholds and a real mount check; it used to measure an empty mount-point folder as if it were the volume (D22's mistake).
- Built: `storage/` on the manifest (`feature/p1-storage`). Tier mounts come from the manifest, coldstore is `/Volumes/coldstore` everywhere, and `setup_direct_mounts.sh` builds its folder list from the media layout. That adds `staging/failed`, `logs/media-watcher` and `logs/takeout`, and drops folders nothing used (`immich/logs`, `logs/system`, `logs/media-processing`, `logs/web`). With nothing left to create on faststore, the storage job no longer trips over D27 at boot. Found and fixed D29: `format_and_mount.sh` could erase a RAID set that holds data.
- Built: `infrastructure/` on the manifest (`feature/p1-infra`). Colima's VM size is in the manifest (4 CPUs, 6 GB, 60 GB: the live VM's), `compose_helpers.sh` finds the Immich folder from any working folder (it only worked from the repo root, and its fallback could never run), and `configure_https.sh` lists the URLs from the mappings file. Fixed on the way: `compose_wrapper.sh` failed under bash 3.2 whenever the service folder had no `.env`.
- Built: `services/` on the manifest (`feature/p1-services`). Plex and Jellyfin start through one routine (`lib/native_app.sh`) that takes the app, health URL, port and data tier from the manifest, won't start an app whose data tier isn't mounted, and always puts the tailnet mappings back; this fixed D30. The landing port, the Immich folder and both configure scripts read the manifest, and `configure_jellyfin.sh` no longer runs `chown -R` over Jellyfin's data.
- Built: `automation/` on the manifest (`feature/p1-automation`). `configure_launchd.sh` takes its jobs and their order from the manifest, can install one job, keeps held jobs held, and refuses to load jobs from a linked git worktree. `setup_media_processing.sh` had never worked since the scripts moved (wrong repo root, a processor path that doesn't exist) and would have installed the watcher plist with `__REPO__` unfilled; it now builds on the storage and LaunchD scripts.
- Built: `media/` on the manifest (`feature/p1-media`): the kebab-case layout (D10), nothing written until the media tier is mounted (D26), and the processor's counters (D30). Testing it end to end found four more faults, all fixed: the watcher ran the processor with no option, which only prints usage, so nothing was ever processed; one bad file stopped the whole run and the summary counts were always 0; `--movies-only` and its siblings died on their first log line; and the usual release name `Show.Name.S01E02` didn't parse.
- Built: `takeout/` on the manifest (`feature/p1-takeout`). The import wrapper's default folders are the manifest's, and it won't create its output folder (hundreds of GB) on a tier that isn't mounted. The importer logs under the manifest's log root only when that volume is mounted, else under `~/Library/Logs`.
- Built: diagnostics and the MCP server on the manifest (`feature/p1-diagnostics`). `diag_lib.sh` reads `config/homelab.env` directly (never `scripts/`), so tier mounts, ports and thresholds are the manifest's, with built-in defaults if the file is missing. The MCP server reads the same file with the standard library (its Python has no PyYAML): coldstore is `/Volumes/coldstore` there too. Found and fixed D31: the storage diagnostics took an empty mount-point folder for the volume.
- Built: the CLAUDE.md update (`feature/p1-claude-md`). It adds the manifest and the manifest-first rule, the Python packages in the dependency graph, Python conventions for them, how LaunchD jobs are rendered and held, and the safety rules the defects taught (no mount-point folders, no recursive chown or chmod, no erasing a set that holds data, no `((n++))` under `set -e`).
- **Phase 1 is built and deployed (2026-11-26).**
  - **Rehearsal:** a VM rehearsal of `mcp-refactor` at `5377c14` passed (run `homelab-rehearsal-20261126-175604`). After the repo move and a clean reboot, every job exits 0 apart from the two Docker jobs, which can't run in a VM. The media watcher waits for warmstore instead of crash-looping. MCP, Plex and Jellyfin answer, both backups restore, and the VM's faststore and the host's real data are unchanged.
  - **Deploy:** the mini's `deployed` branch was fast-forwarded to `5377c14` (tag `deploy-2026-11-26-p1`) and `configure_launchd.sh` re-run from the main checkout. Seven jobs loaded; Colima, the Immich job and the media watcher stayed held.
  - **Checks:** every loaded job exits 0, the storage job included, since it has nothing left to create on faststore. MCP serves 20 tools over the tailnet. `system_overview` reports warmstore's empty folder as not mounted, in 2.9 KB. `run_all.sh`: 13 passed, 1 failed (mounts: warmstore offline, D21). `data_guard.py verify`: no unexpected changes.

**Acceptance:** `grep -rn "/Volumes/Media\|/Volumes/Photos" scripts diagnostics` returns nothing. Every diagnostic emits valid JSON in JSON mode (schema test). `system_overview` returns under 2 KB on a healthy box.

## Phase 2 — Control plane and full read-only surface

- `homelab/` package: `exec.py` (allowlist, TEST_MODE fixtures), adapters (launchd, docker, diskutil `-plist`, tailscale json, brew), and API adapters for Immich, Plex and Jellyfin with Keychain secrets.
- All T0 tools from 03, plus `storage_plan_recovery`. This includes the read-only curation reports (album profiles, unsorted photos, unmatched or mismatched movies), so you can see the size of the job before anything is written.
- `state.db` with migrations, the snapshot LaunchD job `io.homelab.snapshot`, `history_query`, automatic incidents, `memory_*` and `incident_*` tools, nightly DB copy to coldstore.
- Resources, prompts, `docs_search`/`runbook_get` (FTS5), `instructions.md`.
- `homelab` CLI exposing the same domain functions for humans.

**Progress** (2026-11-27):
- Built: `homelab/exec.py` (the allowlist, fixed program paths, timeouts that kill the process group, TEST_MODE fixtures; the T3 commands always refused), `redact.py`, and `config/homelab.json` so the LaunchD Python reads the manifest without PyYAML (#42).
- Built: read-only adapters for diskutil, launchctl, Tailscale, Docker, Homebrew, power and SMART, tested against output recorded on the mini (#43). Keychain secrets (`homelab secrets`) and the Immich, Plex and Jellyfin API adapters (#44).
- Built: the T0 tools on the domains, `system_overview` rebuilt on the adapters (0.4 s, 1.9 KB live), `storage_plan_recovery`, the `homelab status` and `homelab tool` commands, and the manifest's `power:` profile (#45). `media_staging_list`, `media_library_stats`, `photos_stats`, `updates_check` (#46).
- Built: `state.db` with migrations, `io.homelab.snapshot` every 15 minutes, `history_query`, automatic incidents (one per failing component, reopened within an hour so flapping makes one), `memory_*` and `incident_*`, retention, and the daily copy to coldstore (#47).
- Built: the operating guide in `initialize`, resources, prompts, `docs_search` and `runbook_get` over FTS5, and the tool-schema portability lint with the committed `tools/list` surface; CI now runs the MCP tests (#48). The read-only curation reports: albums, album profiles, unsorted photos, and movies joined across Plex and Jellyfin (#49).
- Found: D32. Every step was gated, merged into `mcp-refactor`, and the merged branch tested from a clean clone before going on.
- Built: the Phase 2 step in the VM rehearsal (#51).
- **Phase 2 is built and deployed (2026-11-27).**
  - **Rehearsal:** a VM rehearsal of `35f1e15` passed (run `homelab-rehearsal-20261127-045816`). That tree is the deployed code; the deployed commit adds only docs. In the VM:
    - every job exits 0, the snapshot job included, apart from the two Docker jobs;
    - MCP serves 49 tools, with the guide, resources and prompts;
    - **unmounting faststore opened an incident at the next snapshot, and remounting it resolved it;**
    - history answered from the snapshots;
    - both data guards were unchanged.
  - **Deploy:** the mini's `deployed` branch was fast-forwarded to `8976ed5` (tag `deploy-2026-11-27-p2`), and `configure_launchd.sh snapshot mcp` installed the new job and restarted MCP. Nothing else was reloaded.
  - **Checks:**
    - The snapshot job's first run under LaunchD exited 0. It read faststore's usage (D27 doesn't affect Python), recorded the five versions, and opened one incident: warmstore not mounted (D21).
    - MCP serves 49 tools over the tailnet, and history, incidents, doc search and the recovery plan all answer.
    - Every loaded job exits 0.
    - `run_all.sh`: 13 passed, 1 failed (warmstore offline, D21).
    - `data_guard.py verify`: no unexpected changes.
  - **After the deploy:** `system_overview` measured 2.07 KB on the mini with its open incident listed. It now gives the incident count only (2.0 KB), shipping with the next deploy.
- Still to do: the API keys (`homelab secrets …`). Without them, the library, photo and curation tools say which key is missing, and the curation adapters haven't run against the live APIs.

**Acceptance:** "When did warmstore last exceed 80%?" is answerable from history. Unplugging a test volume opens an incident within 15 minutes, and remounting it resolves the incident. Tool-schema portability lint passes (names, flat schemas, OpenAI strict, Gemini subset).

## Phase 3 — Policy, auth, audit, jobs, safe actions

- `policy.yaml` with startup validation. Bearer tokens + scopes. Tailscale identity capture. Audit table + JSONL.
- Job runner with progress protocol, locks and restart reconciliation.
- Scoped sudoers (`/etc/sudoers.d/homelab`) installed via setup, with `visudo -c`.
- T1 tools: `service_restart/start`, `launchd_kickstart`, `media_process`, `media_retry_failed`, `library_scan`, `photos_run_job`, `tailscale_serve_reconcile`, `storage_ensure_layout`, `power_ensure`, `logs_collect`, `job_*`.
- Rewrite `docs/MCP.md` "Constraints" to describe the tier model.

**Progress** (2026-11-27):
- Built: `config/policy.yaml` and `homelab/policy.py`: every tool's tier, the four scopes, the `core` toolset, the T1 rate limit and dry-run default, lock keys, and the names that are never exposed. The server refuses to start if a registered tool is missing from the policy, if the policy lists one that isn't registered, or if a T3 name is registered. `config/policy.json` is rendered for the LaunchD Python (#53).
- Built: bearer tokens (`homelab token create|list|revoke`, kept hashed in `state.db`), with `tools/list` filtered by the token's scope and toolset and every call checked again; the T1 rate limit (10 a minute per token); the audit log (every call, refused ones included, with the token, Tailscale user, model, redacted arguments and outcome; mirrored to `audit.jsonl` while warmstore is mounted) and `audit_recent` (#54). Requests without a valid token get 401.
- Built: the job runner (`homelab/jobs.py`, migration 0003). Each job runs under its own detached supervisor, which holds a lock file for as long as it lives, waits as `queued` for the job's lock and one of two slots, runs the argv through `homelab.exec` (checked again), reads `::progress`, `::stage` and `::result` lines, and records the outcome; a timeout or `job_cancel` stops the job's process group. Jobs survive the process that started them, and jobs whose supervisor is gone are marked `lost`. `job_status`, `job_logs`, `job_list`, `job_cancel` (#55).
- Built: the scoped sudo rule. `scripts/core/install_sudoers.sh` installs `/etc/sudoers.d/homelab` after `visudo -c` and a confirmation, and takes it out again if the whole sudo configuration then fails to check. It allows exactly `pmset -a <setting> <value>` for the manifest's power profile; `tailscale serve` needs no sudo here, and `diskutil` has no rule. `homelab.exec` allows `sudo -n` only for those same commands (#56).
- Built: the T1 actions, all dry runs unless called with `dry_run=false`, each checking the manifest's dependencies first: `service_restart`, `service_start`, `launchd_kickstart`, `media_process`, `media_retry_failed`, `library_scan` (refused while the media tier is unmounted), `photos_run_job`, `tailscale_serve_reconcile`, `storage_ensure_layout`, `power_ensure`, `logs_collect` (a redacted bundle). Slow ones are jobs on their policy lock. The MCP server, Tailscale and Colima are never restarted from here. Fixed D32: the Plex and Jellyfin jobs now stay in the foreground while the app answers (#57).
- Built: the Phase 3 step in the VM rehearsal (#58), and the docs (#59): `docs/MCP.md` "Constraints" now describes tokens, tiers and the audit log, and lists the actions and jobs.
- Not in Phase 3, by design: T2 tools and `plan_*` (Phase 5), the `curator` tools beyond the read-only reports and the local-only photo listener (Phase 6), push notifications on job completion (with the Phase 5 push channel).

**Acceptance:** policy tests prove that T3 names are absent from `tools/list` for every scope, that an `observe` token can't call T1, that `dry_run` defaults to true, that two `media_process` calls serialize, and that a job survives a server restart.

## Phase 4 — Harness and evals

- `agent/` per 06: LiteLLM, MCP client, profiles, auto-recall, compaction, approval interception, json_react fallback.
- About 30 eval scenarios with fixtures, and the compatibility matrix across at least one local and two cloud providers.
- Headless `weekly_maintenance` LaunchD job with an observe-scoped token.
- `mcpo` instructions for Open WebUI.
- Local model per [09](09-local-model.md):
  - an `io.homelab.ollama` LaunchD job (Homebrew `ollama serve`, `127.0.0.1` only)
  - `qwen3.5:9b` pinned by digest
  - the memory guard before scheduled runs
  - the operating-guide rules from `probe.py`
  - dry-run and plan results rendered from the server's envelope
  - `tests/e2e/local_model/probe.py` replaced by the eval suite as the gate

**Acceptance:** at least two non-Claude providers (one local) are marked **supported**. 100% pass on the safety and injection scenarios for every supported profile.

## Phase 5 — Changes with approval

- Plan/approve/execute flow: `plans` table, push approval (ntfy or Pushover), `homelab plan approve`, harness approval UI.
- Version pinning: commit the `IMMICH_VERSION` compose change, add it to `.env.example`, record versions in `versions`, and implement `updates_apply`/`updates_rollback` with a mandatory `photos_backup_db` guard.
- Make `photos_import_takeout` a job: non-interactive importer, progress lines, space guard.
- `service_stop`, `config_set` (writes `homelab.local.yaml` only), `launchd_install`.
- Re-enable a scheduled update job, but have it only create a *plan* and notify. Nothing auto-applies.

**Acceptance:** an Immich upgrade end-to-end from a non-Claude model, with the approval arriving by push, a DB backup taken, and a rollback tested. A plan with changed args or past its expiry is rejected.

## Phase 6 — Curation: Immich albums and movie metadata

Depends on Phase 2 (adapters), Phase 3 (jobs, scopes) and Phase 5 (approvals). The design is in [08-curation.md](08-curation.md).

- **Fix photo dates first (D20)**, because date-based album rules depend on them.
- **Verify first:** which provider-ID folder form (`{tmdb-…}`, `[tmdbid-…]` or both) Plex 1.42 and Jellyfin 10.11 both honor.
- **Access:** create the restricted Immich API key, the `curator` scope and the `photo_access` token property.
- **Photos:** album profiles, rule tests, review-album proposals, `review_apply`, the feedback table, tags, archive, sorting unsorted photos, new-album suggestions, undo.
- **Movies:**
  - Join Plex and Jellyfin by file path.
  - Add match candidates and `media_fix_match` with candidate validation.
  - Add labels and collections, with access-label protection.
  - Run `media_enrich` at ingest and as a backfill job.
  - Rename folders to carry the ID at ingest.
- **Rules:** the rules file and engine, plus the nightly `io.homelab.curate` LaunchD job.
- **Evals:** the curation scenarios.

**Acceptance:**
- A proposal for an existing album, pruned in the Immich app and approved by push, lands in the album. The removed photos are never proposed again, and the whole change can be undone.
- A new `Dune.2021.2160p…` file ends up matched to *Dune* (2021) on both servers with the same TMDB ID. At most one approval is needed, and only if the match was uncertain.
- Policy tests show that no scope can delete, trash or share a photo. They also show that no scope can add the Toddler label without approval, or at all to an item outside G / TV-Y or with an excluded genre.
- `docs/PARENTAL-CONTROLS.md` lists the exact Plex and Jellyfin settings for the toddler profile, and you've applied them.
- Curation works end to end with a text-only local model.

## Phase 7 — Proactive operations (optional)

- Incident-triggered read-only triage runs. Findings attach to the incident and go out as a push.
- Capacity forecasting from metrics ("warmstore full in ~41 days").
- SMART trend alerts using inventory baselines.
- A monthly report artifact.

---

## Testing additions (all phases)

| Suite | What |
|---|---|
| `tests/homelab/` (pytest) | Adapters against recorded CLI/API fixtures (`diskutil -plist` samples of degraded/rebuilding sets, `launchctl print`, `docker ps` json) |
| `tests/mcp/` (pytest + MCP client SDK) | In-process server: envelope schema, scope filtering, policy, redaction (seeded secrets never appear), path traversal rejection, T3 absence |
| `tests/mcp/test_schema_portability.py` | Every tool's name and schema validated against OpenAI strict + Gemini subset rules. Snapshot of `tools/list` committed. A diff requires review |
| `tests/unit/*.bats` | Existing, plus `DIAG_FORMAT=json` output validity, and `environment.sh` fallbacks when `homelab.env` is missing |
| `tests/evals/` | Phase 4 scenarios; nightly with a local model |

All new tests set `TEST_MODE=1`. In `TEST_MODE`, `exec.py` refuses any non-fixture command, which is a stronger guarantee than relying on each script to check the flag.

## Open decisions (need your call)

1. **Push channel for approvals:** ntfy (self-hostable, simple) or Pushover (paid, polished iOS app)?
2. **Where the local model runs: decided.** On the mini: Qwen3.5-9B through Ollama on `127.0.0.1`, loaded on demand ([09](09-local-model.md)). It's measured good for ops triage and not yet cleared for curation.
3. **Media path canonical form: decided** (2026-11-26). kebab-case (`movies`, `tv-shows`, `staging/...`): Plex's and Jellyfin's libraries already read those folders, and `setup_direct_mounts.sh` creates them.
4. **Python packaging: decided** (2026-11-26). One `pyproject.toml` at the repo root.
5. **Whose photo library: decided.** Per Immich user. Each person creates their own restricted key, and each curator token is bound to one user.
6. **Thumbnails to cloud models: decided.** Local only. Photos never leave the mini.
7. **Parental controls: decided.** A fail-closed `Toddler` allow-list for the 2-year-old's profile: G / TV-Y only, with a parent approving every addition (08).
8. **Coldstore volume name: decided** (2026-11-26). `coldstore`, mounted at `/Volumes/coldstore`, as `create_hdd_raid.sh` already names it (D25). The disk is renamed when it is next attached.
