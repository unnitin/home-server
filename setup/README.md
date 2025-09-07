
# Setup Scripts

This folder contains the entrypoints for setting up your Mac mini HomeServer.

## Scripts

- **setup.sh**  
  Safe bootstrap (Homebrew + CLI tools only). Run this first to prepare your environment.  
  ```bash
  setup/setup.sh
  ```

- **setup_full.sh**  
  Interactive full setup. Installs Docker/Colima, Immich, Plex, launchd jobs, Tailscale, and optional reverse proxy. Prompts you before destructive storage rebuilds.  
  ```bash
  setup/setup_full.sh
  ```

- **setup_flags.sh**  
  Non-interactive, flag-driven setup. Lets you choose exactly which steps to run with command-line flags.  
  ```bash
  setup/setup_flags.sh --all
  ```

  Common flags:
  - `--all` → bootstrap + Colima + Immich + Plex + launchd + tailscale-install + tailscale-serve-direct  
  - `--rebuild=<targets>` → rebuild storage arrays (faststore, warmstore, coldstore). Requires `RAID_I_UNDERSTAND_DATA_LOSS=1` and disk envs.  
  - `--format-mount` → after rebuild, format & mount arrays.  
  - `--enable-proxy` → install & enable Caddy reverse proxy.  
  - `--tailscale-up` → run `sudo tailscale up`.  

  Use `--help` for the full list.

## Recommended use

1. Start with `setup.sh` to bootstrap.  
2. Run `setup_full.sh` if you want an interactive guided setup.  
3. Use `setup_flags.sh` for scripted/automated installs.

See [../README-QUICKSTART.md](../README-QUICKSTART.md) for common usage examples.


## Examples for `setup_flags.sh`

- **Full typical install (no storage rebuilds):**
  ```bash
  setup/setup_flags.sh --all
  ```

- **Safe bootstrap + Docker + Immich only:**
  ```bash
  setup/setup_flags.sh --bootstrap --colima --immich
  ```

- **Rebuild warmstore as a 2‑disk mirror (⚠️ destructive):**
  ```bash
  export SSD_DISKS="disk4 disk5"
  export RAID_I_UNDERSTAND_DATA_LOSS=1
  setup/setup_flags.sh --rebuild=warmstore --format-mount
  ```

- **Install Tailscale, bring it up, and serve Plex + Immich over HTTPS:**
  ```bash
  setup/setup_flags.sh --tailscale-install --tailscale-up --tailscale-serve-direct
  ```

- **Enable the reverse proxy (Caddy) for single-origin browser access:**
  ```bash
  setup/setup_flags.sh --enable-proxy
  ```

For the full list of flags, run:
```bash
setup/setup_flags.sh --help
```
