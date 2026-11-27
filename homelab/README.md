# homelab/: the control plane

The Python side of the home server (docs/mcp-refactor/02-architecture.md).

| Module | What |
|---|---|
| `config.py` | loads, validates and renders the manifest |
| `envfile.py` | reads `config/homelab.env` with the standard library |
| `exec.py` | the one way to run a program: allowlist, timeouts, TEST_MODE fixtures |
| `redact.py` | removes secrets from anything a tool returns |
| `adapters/diskutil.py` | RAID sets, members, volumes, usage, orphaned members (`diskutil -plist`) |
| `adapters/launchd.py` | `io.homelab.*` jobs: loaded, held, pid, last exit, runs |
| `adapters/tailscale.py` | connection, serve mappings, drift from the manifest, Funnel |
| `adapters/docker.py` | compose project containers: state, health, restarts |
| `adapters/brew.py` | outdated formulae and casks |
| `adapters/system.py` | power settings, uptime, macOS version, SMART |
| `adapters/http.py` | HTTP to services on the mini (localhost only; fixtures under TEST_MODE) |
| `adapters/immich_api.py` | Immich version, library totals, background job queues |
| `adapters/plex_api.py` | Plex version, library sections with item counts, recently added |
| `adapters/jellyfin_api.py` | Jellyfin version, item counts, libraries, last library scan |
| `secrets.py` | API secrets in the login Keychain (service `homelab`) |

The adapters are read-only and return plain dataclasses; tests run them against
output recorded on the mini (`tests/fixtures/exec/`).

| Module | What |
|---|---|
| `result.py` | the envelope every tool returns: worst-first checks, a summary under 200 characters, redacted, capped at 8 KB |
| `domains/storage.py` | `storage_status`, and `storage_plan_recovery` (plans only, for a person to run) |
| `domains/services.py` | `service_status`, `launchd_jobs`, `docker_containers` |
| `domains/logs.py` | `service_logs`, `logs_search` (log text is returned as data, not instructions) |
| `domains/network.py` | `network_check_port` (the mini's own ports), `tailscale_status` |
| `domains/system.py` | `power_status` (against the manifest's `power:` profile), `config_get` |
| `domains/health.py` | `system_overview`, built on the above, in parallel |
| `tools.py` | the tools by name, shared by the MCP server and the CLI; a failure becomes an error result |

```bash
python3 -m homelab status                         # the overview, as text (--json for the envelope)
python3 -m homelab tool --list                    # every read-only tool
python3 -m homelab tool storage_status tier=warmstore
python3 -m homelab tool service_logs service=plex lines=50 grep=error
```

The state database (history, incidents, memory) follows in Phase 2.

## The manifest

`config/homelab.yaml` is the single source of truth for storage tiers, services, ports,
LaunchD labels, health endpoints, tailnet mappings and media paths. After editing it:

```bash
python3 -m homelab config render     # rewrite homelab.env, homelab.json, tailscale_serve.txt
python3 -m homelab config validate   # check the manifest (and config/homelab.local.yaml)
python3 -m homelab config get media  # print a section as JSON
```

Commit the regenerated files with the manifest; `tests/unit/test_manifest.py` fails while
they're stale. Bash reads `config/homelab.env` through `scripts/core/environment.sh`, so
nothing on the mini needs Python packages to read its configuration.

Per-machine overrides go in `config/homelab.local.yaml` (gitignored). `render` turns them
into `config/homelab.local.env`, holding only the values they change, and
`config/homelab.local.json`.

Python on the mini doesn't need PyYAML either: the LaunchD Python has pydantic but
not PyYAML, so `config.load()` reads `config/homelab.json` (the validated manifest,
committed and kept current by the same test) when PyYAML is missing.

## Running programs

Everything the control plane runs goes through `homelab.exec.run(argv)`:

- a name from its allowlist, found at a fixed path, never on `PATH`;
- only read-only uses in Phase 2. The disk-erasing storage scripts and
  `diskutil erase*`/`appleRAID create|delete` are refused, always
  (`tests/homelab/test_exec.py`);
- under `TEST_MODE=1` nothing runs: results come from `tests/fixtures/exec/`.

## API secrets

Immich, Plex and Jellyfin answer most API calls only with a key. The manifest names
each one (`services.<name>.api.secret`); they live in the login Keychain:

```bash
python3 -m homelab secrets list               # which are set (never the values)
python3 -m homelab secrets set immich_api_key # Immich: Account settings → API keys (an admin's)
python3 -m homelab secrets set jellyfin_api_key  # Jellyfin: Dashboard → API Keys
python3 -m homelab secrets import-plex        # copies Plex's own token from its preferences
```

`set` asks for the value without echoing it and passes it to `security` on stdin,
so it never appears in `ps` or shell history. No MCP tool can write a secret. A
value read is removed from every result (`redact.py`), and a tool that needs a
missing one says which command sets it.

## Requirements

Python 3.11+, with `pydantic`, and `PyYAML` to render (`pip install -e .` from the repo root, or
`pip install -e '.[mcp,dev]'` for the MCP server and the test tools).
