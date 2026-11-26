# homelab/: the control plane

The Python side of the home server (docs/mcp-refactor/02-architecture.md). Today it
holds the manifest loader; adapters, domains and the state database follow in Phase 2.

## The manifest

`config/homelab.yaml` is the single source of truth for storage tiers, services, ports,
LaunchD labels, health endpoints, tailnet mappings and media paths. After editing it:

```bash
python3 -m homelab config render     # rewrite config/homelab.env and config/tailscale_serve.txt
python3 -m homelab config validate   # check the manifest (and config/homelab.local.yaml)
python3 -m homelab config get media  # print a section as JSON
```

Commit the regenerated files with the manifest; `tests/unit/test_manifest.py` fails while
they're stale. Bash reads `config/homelab.env` through `scripts/core/environment.sh`, so
nothing on the mini needs Python packages to read its configuration.

Per-machine overrides go in `config/homelab.local.yaml` (gitignored). `render` turns them
into `config/homelab.local.env`, holding only the values they change.

## Requirements

Python 3.11+, with `pydantic` and `PyYAML` (`pip install -e .` from the repo root, or
`pip install -e '.[mcp,dev]'` for the MCP server and the test tools).
