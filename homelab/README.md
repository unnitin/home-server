# homelab/: the control plane

The Python side of the home server (docs/mcp-refactor/02-architecture.md).

| Module | What |
|---|---|
| `config.py` | loads, validates and renders the manifest |
| `envfile.py` | reads `config/homelab.env` with the standard library |
| `exec.py` | the one way to run a program: allowlist, timeouts, TEST_MODE fixtures |
| `redact.py` | removes secrets from anything a tool returns |

Adapters, domains and the state database follow in Phase 2.

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

## Requirements

Python 3.11+, with `pydantic`, and `PyYAML` to render (`pip install -e .` from the repo root, or
`pip install -e '.[mcp,dev]'` for the MCP server and the test tools).
