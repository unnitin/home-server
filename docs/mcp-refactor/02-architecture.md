# 02 — Target Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Clients (any LLM)                                                        │
│  agent/ CLI (LiteLLM → Ollama | OpenAI | Gemini | Anthropic | Bedrock…)  │
│  Claude Desktop / Cursor / Goose / LM Studio (native MCP)                │
│  Open WebUI / LibreChat (via mcpo → OpenAPI)                             │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ https://<mini>.<tailnet>.ts.net:8765/mcp  (tailscale serve: tailnet only)
                │ → 127.0.0.1:18765 on the mini · or stdio when running on the mini itself
┌───────────────▼──────────────────────────────────────────────────────────┐
│ homelab_mcp/  — thin protocol layer                                      │
│  auth (bearer token → scopes) · tool registry · policy gate · audit      │
│  structured results · resources/prompts (+ tool mirrors) · job endpoints │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ plain Python calls
┌───────────────▼──────────────────────────────────────────────────────────┐
│ homelab/  — control plane (pip-installable, no MCP dependency)           │
│  config (manifest) · domains (health, storage, services, media, photos,  │
│  updates, logs, memory) · adapters (launchctl, docker, diskutil,         │
│  tailscale, brew, immich/plex/jellyfin HTTP) · exec · jobs · state (DB)  │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ subprocess (argv lists, never shell strings) / HTTP
┌───────────────▼──────────────────────────────────────────────────────────┐
│ Executors (existing)                                                     │
│  scripts/**.sh · diagnostics/*.sh · CLIs · service REST APIs             │
└──────────────────────────────────────────────────────────────────────────┘
        ▲ config/homelab.yaml (+ generated config/homelab.env) read by all layers
        ▲ state.db on INTERNAL disk (~/Library/Application Support/homelab/)
```

**Why a Python control plane and not "MCP wraps bash" (today's model):**
- Parsing is the hard part. `diskutil appleRAID list -plist`, `launchctl print`, `docker compose ps --format json` and `tailscale status --json` all give structured data that Python handles reliably and bash doesn't.
- The HTTP APIs (Immich `/api/server/statistics` and `/api/jobs`, Plex `/library/sections`, Jellyfin `/System/Info`) need auth headers and JSON handling.
- Jobs, policy, audit and memory need a process that keeps state.

**Why not rewrite everything in Python:** boot-time LaunchD scripts and `setup/` must run before any venv exists, and `diagnostics/` must keep working when Python or the repo is half-broken. Those stay in bash. Python *calls* them, and nothing is reimplemented.

## Dependency graph (additions)

```
scripts/{core…takeout}   (unchanged)
diagnostics/             (standalone; reads config/homelab.env with fallbacks)
homelab/                 → depends on: scripts/* (as executors), diagnostics/ (as executors), config/
homelab_mcp/             → depends on: homelab/
agent/                   → depends on: MCP protocol only (never imports homelab/)
```

`agent/` deliberately talks to the server only over MCP, so it works against any MCP server, and the server works with any client.

## The manifest: `config/homelab.yaml`

This is the single source of truth. It's committed and holds no secrets. Per-machine overrides go in `config/homelab.local.yaml` (gitignored). The real file is `config/homelab.yaml`; the excerpt below shows its shape.

```yaml
host:
  name: hakuna
  repo_root: auto            # resolved at runtime; never a /Users/... literal

storage:
  state_dir: "~/Library/Application Support/homelab"   # internal disk, survives RAID failure
  log_root: /Volumes/warmstore/logs
  tiers:
    faststore: { mount: /Volumes/faststore, media: nvme, raid: mirror, warn_pct: 80, crit_pct: 90 }
    warmstore: { mount: /Volumes/warmstore, media: ssd,  raid: mirror, warn_pct: 85, crit_pct: 95 }
    coldstore: { mount: /Volumes/coldstore, media: hdd,  raid: mirror }   # decided 2026-11-26: no longer Archive (D25)

services:
  colima:
    kind: runtime
    launchd: io.homelab.colima
    health: { cmd: [docker, info] }
  immich:
    kind: compose
    compose_dir: services/immich
    version_env: IMMICH_VERSION          # pinned in services/immich/.env
    ports: [2283]
    health: { http: "http://localhost:2283/api/server/ping", expect: 200 }
    depends_on: [colima, faststore]
    launchd: io.homelab.compose.immich
    api: { base: "http://localhost:2283/api", secret: immich_api_key }
  plex:
    kind: native_app
    app: "Plex Media Server"
    ports: [32400]
    health: { http: "http://localhost:32400/identity", expect: 200 }
    depends_on: [warmstore]
    launchd: io.homelab.plex
    api: { base: "http://localhost:32400", secret: plex_token }
  jellyfin:
    kind: native_app
    ports: [8096]
    health: { http: "http://localhost:8096/health", expect: 200 }
    depends_on: [warmstore]
    launchd: io.homelab.jellyfin
    api: { base: "http://localhost:8096", secret: jellyfin_api_key }
  landing:
    kind: process
    ports: [8080]
    launchd: io.homelab.landing
  media_watcher:
    kind: process
    launchd: io.homelab.media.watcher
  mcp:
    kind: process
    listen: "127.0.0.1:18765"            # loopback only; the tailnet reaches it on :8765 (remote_access)
    launchd: io.homelab.mcp

boot_order: [storage, powermgmt, colima, immich, plex, jellyfin, tailscale, landing, media_watcher, mcp]

remote_access:
  tailscale_serve:                       # the ONLY list of tailnet mappings (fixes D17); Serve, never Funnel
    - { https: 443,   target: "http://localhost:8080" }     # landing page
    - { https: 2283,  target: "http://localhost:2283" }     # Immich
    - { https: 32400, target: "http://localhost:32400" }    # Plex
    - { https: 8096,  target: "http://localhost:8096" }     # Jellyfin
    - { https: 8765,  target: "http://127.0.0.1:18765" }    # MCP server

media:                                    # ONE layout (fixes D10): kebab-case, decided 2026-11-26
  tier: warmstore
  staging: staging
  failed: staging/failed
  libraries:
    movies:      { dir: movies,      staging: movies }
    tv:          { dir: tv-shows,    staging: tv-shows }
    collections: { dir: collections, staging: collections }

photos:
  library: /Volumes/faststore/immich
  takeout_work_dir: /Volumes/faststore/takeout-work

curation:                                 # 08-curation.md; the rules themselves live in config/curation.yaml
  photos:
    review_album_prefix: "Review: "
    direct_add_max: 20                    # per call, private albums only; above this → approval
    auto_apply_max_per_night: 200         # per album
  media:
    access_labels:                        # allow-list labels: a profile sees ONLY items carrying its label
      Toddler:
        allowed_ratings: [G, TV-Y]        # or the regional equivalent; unrated never qualifies
        excluded_genres: [Horror, Thriller, Crime, War, Mystery]
        add: approval_always              # no rule may auto-apply it
        remove: no_approval               # pulling an item is the safe direction
    rename_window_hours: 24               # ID renames only for items this new and never played
```

**How each layer consumes it:**
- `homelab/config.py` loads and validates it with pydantic, then merges the local overrides.
- `python3 -m homelab config render` writes `config/homelab.env` (flat `HOMELAB_*` vars for bash) and `config/tailscale_serve.txt`. Both are generated but **committed**, and a test fails while either is stale. Committing them means bash on the mini never needs Python packages to read its config: the LaunchD Python has pydantic but no PyYAML, and `/usr/bin/python3` has neither. Local overrides render into `config/homelab.local.env` (gitignored), holding only the values they change.
- `scripts/core/environment.sh` (named in CLAUDE.md but missing today, D12) sources `config/homelab.env`, then `homelab.local.env` if present. Every module sources it.
- `diagnostics/diag_lib.sh` sources `config/homelab.env` directly if it's present, which keeps diagnostics standalone.
- `scripts/automation/configure_launchd.sh` renders plists from templates with values from the manifest (labels, log paths under `log_root`).
- `homelab_mcp/` builds enum values for tools from it, e.g. `service: enum[immich, plex, …]`.

## Structured-output contract

Every tool returns the same envelope, as both MCP `structuredContent` (with an `outputSchema`) and a compact text rendering for clients that ignore structured content:

```json
{
  "status": "ok | warn | fail | error | pending | approval_required",
  "summary": "Immich healthy; ML container restarted 2x in 24h",
  "data":   { "...tool-specific..." },
  "checks": [ { "id": "immich.http", "status": "ok", "message": "HTTP 200 /api/server/ping", "component": "immich" } ],
  "hints":  [ "Run service_logs(service='immich', container='immich-ml')" ],
  "truncated": false,
  "job_id": null
}
```

Rules:
- `summary` stays under 200 characters, and `checks` keeps only non-OK items unless `verbose=true`. That keeps small models inside their context limits.
- `hints` are suggested next tool calls. They help weaker models chain calls correctly.
- No ANSI codes (`NO_COLOR=1` is exported to every subprocess, and output is also stripped).
- Every result passes through a redaction filter: API keys, `X-Plex-Token`, `IMMICH_DB_PASSWORD`, bearer tokens.
- Hard cap of about 8 KB of text per result. Anything longer is truncated, with `truncated: true` and a pointer to a log tool.

**Diagnostics JSON mode:** `diag_lib.sh` keeps its `ok`/`warn`/`fail` API. With `DIAG_FORMAT=json` it emits one JSON object per check, plus a final summary object, on stdout. Human output is unchanged. This is a small, contained change to one file, and every diagnostic script gets machine output for free.

## Repo layout after refactor

```
config/
  homelab.yaml                 # manifest (committed)
  homelab.local.yaml           # overrides (gitignored)
  homelab.env                  # generated for bash (committed; a test keeps it current)
  homelab.local.env            # generated from the overrides (gitignored)
  tailscale_serve.txt          # generated tailnet mappings (committed)
  policy.yaml                  # tiers, scopes, approval rules (committed)
  curation.yaml                # album, tag and movie-label rules (gitignored: holds people's names; 08)
homelab/                       # control plane  — pyproject.toml at repo root
  config.py  exec.py  redact.py  jobs.py  policy.py  audit.py
  adapters/  launchd.py docker.py diskutil.py tailscale.py brew.py
             immich_api.py plex_api.py jellyfin_api.py secrets.py
  domains/   health.py storage.py services.py media.py photos.py
             updates.py logs.py network.py memory.py
             curation_photos.py curation_media.py curation_rules.py   # 08
  state/     db.py  migrations/0001_init.sql
  cli.py                       # `homelab ...` CLI: same functions, for humans and LaunchD
homelab_mcp/                   # renamed from mcp/ (fixes D14)
  server.py  envelope.py  auth.py
  tools/     observe.py act.py change.py jobs.py memory.py context.py
  resources.py  prompts.py  instructions.md
agent/                         # LLM-agnostic harness (06-harness.md)
scripts/ diagnostics/ launchd/ services/ setup/   # existing, bash executors
tests/  + tests/mcp/ tests/homelab/ tests/evals/
```

**`exec.py` is the one way to run a subprocess:**
- Takes argv lists only, never `shell=True`.
- Applies a per-call timeout from the manifest or the tool definition.
- Returns `ExecResult{rc, stdout, stderr, duration, timed_out}`.
- Honors `TEST_MODE=1`: it returns fixtures from `tests/fixtures/exec/` and never runs anything that changes state.
- Injects `NO_COLOR=1` and the `HOMELAB_*` env vars.
- Refuses any executable that isn't on an allowlist built from the manifest plus `scripts/`.
