# Mac Mini HomeServer

Final reshipped repository with all scripts, setup, and docs.

### Docker Compose compatibility

This repo includes a wrapper to avoid the “unknown shorthand flag: -d” error when the new Compose plugin isn’t installed.

- Wrapper: `scripts/compose.sh` (auto-detects `docker compose` vs `docker-compose`, and tries Homebrew if missing)
- Patch all shell scripts in-place:
  ```bash
  bash scripts/patch_compose_calls.sh
  ```
- You can also call the wrapper directly in your own commands, e.g.:
  ```bash
  bash scripts/compose.sh up -d
  ```
