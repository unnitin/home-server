
# 🔧 Setup Scripts

This folder contains the entry points for setting up your Mac mini HomeServer.

## 📋 Available Scripts

### **setup.sh** - Safe Bootstrap
Safe bootstrap (Homebrew + CLI tools only). Run this first to prepare your environment.

```bash
setup/setup.sh
```

**What it does**:
- Installs Homebrew package manager
- Adds essential CLI tools (git, curl, rsync, etc.)
- **Safe**: No system modifications or storage changes

---

### **setup_full.sh** - Interactive Setup  
Interactive full setup with confirmations. Installs Docker/Colima, Immich, Plex, launchd jobs, Tailscale, and optional reverse proxy.

```bash
setup/setup_full.sh
```

**Features**:
- **Guided experience**: Prompts for each step
- **Safety checks**: Confirms before destructive operations
- **Flexible**: Skip or customize any component
- **Recommended for**: First-time users

---

### **setup_flags.sh** - Automated Setup
Non-interactive, flag-driven setup. Choose exactly which steps to run with command-line flags.

```bash
setup/setup_flags.sh --all
```

**Common flags**:
- `--all` → Complete setup (bootstrap + services + automation)
- `--bootstrap` → Safe environment setup only
- `--rebuild=<targets>` → Rebuild storage arrays (⚠️ destructive)
- `--format-mount` → Format and mount arrays after rebuild
- `--enable-proxy` → Install & enable Caddy reverse proxy
- `--tailscale-up` → Connect to Tailscale network

**Use `--help` for complete flag reference.**

**Recommended for**: Automated deployments, advanced users

---

## 🎯 Recommended Workflow

### For New Users
1. **📋 [Quick Start Guide](../docs/QUICKSTART.md)** - 30-minute setup
2. **setup.sh** → Safe bootstrap preparation
3. **setup_full.sh** → Interactive guided setup

### For Advanced Users
1. **📖 [Detailed Setup Guide](../docs/SETUP.md)** - Comprehensive walkthrough
2. **setup_flags.sh --all** → Automated complete setup
3. **⚙️ [Environment Variables](../docs/ENVIRONMENT.md)** - Configuration reference

### For Specific Tasks
- **Storage only**: See **💾 [Storage Guide](../docs/STORAGE.md)**
- **Services only**: Use **setup_flags.sh** with specific flags
- **Remote access**: See **🔒 [Tailscale Guide](../docs/TAILSCALE.md)**

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](../docs/QUICKSTART.md)** - Get running in 30 minutes
- **📖 [Detailed Setup Guide](../docs/SETUP.md)** - Step-by-step comprehensive setup
- **⚙️ [Environment Variables](../docs/ENVIRONMENT.md)** - Configuration reference
- **🔧 [Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common issues and solutions


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
