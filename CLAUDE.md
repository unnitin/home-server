# CLAUDE.md — Claude Code Instructions for home-server

## Project Overview

This repository configures a Mac mini as a self-hosted home server running:
- **Plex** — native macOS media server with hardware transcoding
- **Jellyfin** — native/Docker media streaming via Tailscale
- **Immich** — Docker-based photo management (Google Photos alternative)
- **Tailscale** — mesh VPN for encrypted remote access with HTTPS
- **AppleRAID** — three-tier storage (NVMe faststore, SSD warmstore, HDD coldstore)
- **LaunchD** — macOS service automation and boot sequencing

The codebase contains shell scripts organized in 7 modules (plus a standalone `diagnostics/` directory), the manifest `config/homelab.yaml`, a Python control plane (`homelab/`) and MCP server (`homelab_mcp/`), a Python script for Google Takeout import, Docker Compose for Immich, and LaunchD plists for automation. To get a current count: `find scripts/ diagnostics/ -name "*.sh" | wc -l`

The plan behind the current refactor is in `docs/mcp-refactor/` (assessment, architecture, roadmap).

---

## Module Architecture

Scripts depend on each other in this strict order. Never have a lower module depend on a higher one:

```
core/           → system bootstrap, health checks (no dependencies)
storage/        → RAID creation, mounts (depends on: core)
infrastructure/ → Docker/Colima, Tailscale, networking (depends on: core, storage)
services/       → Plex, Jellyfin, Immich deployment (depends on: core, storage, infrastructure)
automation/     → LaunchD, update checks (depends on: all above)
media/          → file watching, processing (depends on: core, storage, services)
takeout/        → Google Photos import (depends on: core, services)
```

Sibling directory (outside the scripts/ module tree):

```
diagnostics/    → health checks and observability (standalone — no dependencies on scripts/)
```

Diagnostics scripts use raw CLI tools directly and do not source from `scripts/core/` or any other module. This is intentional so they can run even if the scripts module tree is broken. They read the manifest's values from `config/homelab.env` directly (in `diag_lib.sh`), with a built-in default for each.

Python, outside the module tree:

```
config/         → the manifest homelab.yaml, and the files generated from it (no code)
homelab/        → control plane: loads and validates the manifest (depends on: config)
homelab_mcp/    → MCP server: runs diagnostics/ in JSON mode, reads config/homelab.env
agent/          → model-agnostic harness (Phase 4, not yet written)
```

**Runtime boot order**: Colima → Storage mounts → Immich containers → Plex → Jellyfin → Tailscale → Media watcher

---

## The Manifest

`config/homelab.yaml` is the single source of truth for storage tiers, services, ports, LaunchD labels, health URLs, tailnet mappings and media paths. **Never hardcode a port, path or label: read it from the manifest.**

- Bash reads it through `config/homelab.env`, flat `HOMELAB_*` variables generated from the YAML. Scripts get them by sourcing `scripts/core/environment.sh`. Diagnostics read the file directly.
- After editing the manifest, run `python3 -m homelab config render` and commit the regenerated `config/homelab.env` and `config/tailscale_serve.txt` with it. `tests/unit/test_manifest.py` fails while they're stale.
- `python3 -m homelab config validate` checks it; `python3 -m homelab config get <section>` prints a section as JSON.
- Per-machine overrides go in `config/homelab.local.yaml` (gitignored); `render` turns them into `config/homelab.local.env`.
- A `HOMELAB_*` variable already set in the environment wins over both files, which is how tests point scripts at a temporary `/Volumes` (`homelab_volumes_at` in `tests/test_helper.bash`).

## Storage Naming Conventions

These names come from the manifest. Use them exactly:

| Name | Device | Mount Point | Use |
|------|--------|-------------|-----|
| `faststore` | NVMe RAID | `/Volumes/faststore` | Photo library (Immich) |
| `warmstore` | SSD RAID | `/Volumes/warmstore` | Media library (Plex/Jellyfin), logs |
| `coldstore` | HDD RAID | `/Volumes/coldstore` | Cold archive storage (named `coldstore` since 2026-11-26; a disk still named `Archive` is renamed with `diskutil rename Archive coldstore`) |

Log directory: `/Volumes/warmstore/logs/{module}/` (the manifest's `storage.log_root`). Media folders are kebab-case: `movies`, `tv-shows`, `collections`, `staging/{movies,tv-shows,collections,failed}`.

A folder under `/Volumes` is not proof that a volume is mounted: macOS leaves empty mount-point folders behind, and writing to one fills the internal disk. Check with `homelab_is_mounted` (scripts) or `diag_is_mounted` (diagnostics), which ask `diskutil`. Never create a mount-point folder.

---

## Shell Script Conventions

Every shell script must follow these patterns. Do not deviate.

### Header / error handling
```bash
#!/usr/bin/env bash
set -euo pipefail
```
All scripts use `set -euo pipefail` — fail fast on errors, unset variables, and pipe failures.

### Sourcing shared libraries
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../core/environment.sh"   # adjust relative path
```
`environment.sh` exports `HOMELAB_REPO` (this checkout's physical path) and every `HOMELAB_*` value from the manifest, and provides `homelab_tier_mount <tier>`, `homelab_is_mounted <path>` and the `log_*` functions below (a script's own `log_*` win).

### Logging
```bash
log_info()    { echo "[INFO]  $(date '+%H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%H:%M:%S') $*" >&2; }
```

### Destructive operation gate
Any script that modifies disks or destroys data must require an explicit environment flag:
```bash
if [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" != "1" ]]; then
    log_error "Set RAID_I_UNDERSTAND_DATA_LOSS=1 to proceed"
    exit 1
fi
```

### No hardcoded user paths
Never write `/Users/someuser/` or any user-specific path in scripts. The pre-commit hook rejects this. Use environment variables or dynamic detection instead.

### Script permissions
All `.sh` files must be executable (`chmod +x`). The pre-commit hook enforces shebangs and executable bits, including on `.bats` and `.py` files that have a shebang.

### Counters under `set -e`
Write `n=$((n + 1))`, never `((n++))`: a post-increment returns 1 when `n` is 0, and under `set -e` that ends the script.

### bash 3.2
LaunchD runs `/bin/bash`, which is bash 3.2. An empty array is unbound under `set -u`: expand it as `${arr[@]+"${arr[@]}"}`.

---

## Python Conventions

One `pyproject.toml` at the repo root covers the Python: `homelab/`, `homelab_mcp/`, `agent/` (later) and `scripts/takeout/`. Python files must:
- Pass `black --line-length=88` formatting
- Pass `flake8 --max-line-length=88 --ignore=E203,W503`
- Use type hints where practical
- Not exceed 88 character line length

The Python LaunchD runs (`/opt/homebrew/bin/python3.11`) has pydantic but no PyYAML. Code that runs on the mini without a development setup, such as `homelab_mcp/`, reads `config/homelab.env` with the standard library and never the YAML.

---

## LaunchD Plist Conventions

All LaunchD service files live in `launchd/` with the naming pattern:
```
io.homelab.{service}.plist
```

Validate syntax before committing:
```bash
plutil -lint launchd/io.homelab.{service}.plist
```

Each plist logs to `/tmp/homelab-<job>.{out,err}` (the manifest's `storage.launchd_log_dir`), which exists before warmstore mounts. Plists are templates: `__REPO__`, `__HOME__` and `__USER__` are filled in by `scripts/automation/configure_launchd.sh`, which takes its jobs and their order from the manifest's `boot_order`.

- `configure_launchd.sh [--render-only] [JOB...]` installs every job, or the ones named.
- A job held with `launchctl disable` stays held: it's rendered but not loaded.
- Jobs are never loaded from a linked git worktree: they'd break when it's removed. Load them from the main checkout.
- Scripts a job runs can't read the external volumes under LaunchD until access is granted (D27).

---

## Environment Variables

Key variables used across scripts:

```bash
# Storage configuration
SSD_DISKS="disk2 disk3"       # SSD RAID members
NVME_DISKS="disk4 disk5"      # NVMe RAID members
COLD_DISKS="disk6 disk7"      # HDD RAID members
RAID_I_UNDERSTAND_DATA_LOSS=1 # Safety gate for destructive ops

# Immich
IMMICH_DB_PASSWORD="..."      # Set in services/immich/.env
IMMICH_SERVER="http://localhost:2283"
IMMICH_API_KEY="..."

# Testing
TEST_MODE=1                   # Suppresses destructive operations in tests

# From the manifest (via environment.sh), for example:
HOMELAB_TIER_FASTSTORE_MOUNT  # /Volumes/faststore
HOMELAB_MEDIA_TV_DIR          # /Volumes/warmstore/tv-shows
HOMELAB_SVC_PLEX_PORTS        # 32400
```
The full list is in `config/homelab.env`.

Never commit actual secrets. The `services/immich/.env` is gitignored. Use `.env.example` as a template.

---

## Testing

### Run tests
```bash
# All unit tests (BATS)
bats tests/unit/

# All Python tests
pytest tests/ -v

# All tests with coverage
pytest tests/ --cov=scripts --cov-report=term-missing

# Security tests
bats tests/security/test_security_validation.bats

# Run BATS unit tests only (fast check)
export TEST_MODE=1 RAID_I_UNDERSTAND_DATA_LOSS=0
bats tests/unit/test_script_validation.bats
```

### Test categories
- `tests/unit/` — script validation, storage utilities, media processing, Python validation
- `tests/integration/` — module dependency ordering, service dependencies, network scenarios
- `tests/e2e/` — full setup workflows, failure recovery, shutdown/reboot scenarios
- `tests/security/` — credential detection, hardcoded path checks

### Adding tests
- Shell script tests: add `.bats` file in the appropriate `tests/` subdirectory using BATS framework
- Python tests: add `test_*.py` in the appropriate subdirectory using pytest
- Always set `TEST_MODE=1` in tests to prevent destructive operations
- Use `tests/test_helper.bash` for shared BATS helpers; `homelab_volumes_at "$BATS_TEST_TMPDIR/Volumes"` moves every manifest path under `/Volumes` to a temporary folder
- Stub `diskutil`, `launchctl`, `tailscale` and the like on `PATH`, and assert the stub is the one found (`command -v`) before running anything that could touch the real system

---

## Pre-commit Hooks

Hooks run automatically on `git commit`:
1. **shellcheck** — lints all `.sh` files (severity: warning+)
2. **check-hardcoded-paths** — rejects `/Users/` in scripts/ and setup/
3. **check-script-docs** — ensures new scripts are documented in `scripts/README.md`
4. **validate-plists** — runs `plutil -lint` on all `.plist` files
5. **detect-private-key** / **detect-aws-credentials** — blocks credential commits
6. **black** / **flake8** — Python formatting
7. **check-yaml** / **check-json** — validates YAML and JSON syntax

Install hooks: `pip install pre-commit && pre-commit install`

---

## Adding a New Script

1. Place it in the correct module directory under `scripts/`
2. Add `#!/usr/bin/env bash` and `set -euo pipefail`
3. Make it executable: `chmod +x scripts/{module}/new_script.sh`
4. Add an entry to `scripts/README.md` (required by pre-commit hook)
5. Add corresponding tests in `tests/unit/` or `tests/integration/`
6. If it's a new service, add a LaunchD plist in `launchd/` and document it in `docs/`
7. Take every port, path and label from `environment.sh`, never a literal

---

## Adding a New Service

0. **Manifest**: add it under `services:` in `config/homelab.yaml` (kind, `launchd` label, ports, health URL), add it to `boot_order`, and add a `remote_access.tailscale_serve` mapping if it's reached over the tailnet. Then `python3 -m homelab config render`
1. **Script**: `scripts/services/install_{service}.sh` and `start_{service}_safe.sh` (a native app can use `start_native_app` from `scripts/services/lib/native_app.sh`)
2. **LaunchD**: `launchd/io.homelab.{service}.plist`
3. **Docs**: `docs/{SERVICE}.md` with setup, troubleshooting, and configuration details
4. **Diagnostics**: `diagnostics/check_{service}.sh`
5. **README**: Update `README.md` to reference the new service and its docs
6. **scripts/README.md**: Add the new scripts

---

## What to Avoid

- **Never touch `setup/setup_flags.sh`** — marked DEPRECATED, broken, do not modify or reference
- **Never hardcode `/Users/...` paths** — pre-commit will reject it
- **Never skip `set -euo pipefail`** in shell scripts
- **Never commit `.env` files** with real credentials
- **Never add module dependencies that go against the dependency graph** (e.g., `core/` importing from `services/`)
- **Never run RAID/disk commands without `TEST_MODE=1`** in tests
- **Do not add files to `venv/`** — the Python virtual environment is local only
- **Never hardcode a port, path or label** — read the manifest
- **Never treat a folder under `/Volumes` as a mounted volume** — ask `diskutil`, and never create a mount-point folder
- **Never `chown -R` or `chmod -R` a volume or a service's data** — it rewrites every existing file's owner and mode
- **Never erase a disk or RAID set that holds a file system** — and erase a blank one only behind `RAID_I_UNDERSTAND_DATA_LOSS=1`
- **Never load LaunchD jobs from a git worktree**

---

## Diagnostics

To check system health, run scripts from `diagnostics/`:
```bash
bash diagnostics/run_all.sh          # Run all health checks
bash diagnostics/full_summary.sh     # Complete system summary
bash diagnostics/check_docker_services.sh
bash diagnostics/check_raid_status.sh
bash diagnostics/check_plex_native.sh
bash diagnostics/check_immich.sh
bash diagnostics/collect_logs.sh     # Collect all logs for debugging
```

---

## Docker / Immich

Immich runs via Docker Compose using Colima as the macOS Docker runtime:
```bash
# Start Colima
scripts/infrastructure/start_docker.sh

# Deploy Immich
scripts/services/deploy_containers.sh

# Or use compose wrapper directly
scripts/infrastructure/compose_wrapper.sh -f services/immich/docker-compose.yml up -d
```

Immich stack: `immich-server`, `immich-machine-learning`, `redis:7-alpine`, `postgres:16-vectorchord`

Config lives in `services/immich/.env`. Copy from `services/immich/.env.example` to start.

---

## Google Takeout Import

```bash
# Run enhanced import (installs deps automatically)
scripts/takeout/enhanced_takeout_import.sh /path/to/takeout.zip

# Or run Python directly
python3 scripts/takeout/enhanced_takeout_import.py \
  --input /path/to/takeout \
  --output /Volumes/faststore/photos
```

The Python script preserves EXIF metadata, GPS data, and handles HEIC conversion. It requires `pillow`, `piexif`, and optionally `ffmpeg` for video.
