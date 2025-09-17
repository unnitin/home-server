
# 🔧 Setup Scripts

This folder contains the entry points for setting up your Mac mini HomeServer.

**📖 For detailed script documentation**: → [**🛠️ Scripts Reference**](../scripts/README.md)

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
Interactive full setup with confirmations. Installs Docker/Colima, Immich, Plex, media processing automation, launchd jobs, and Tailscale.

```bash
setup/setup_full.sh
```

**Features**:
- **Guided experience**: Prompts for each step
- **Safety checks**: Confirms before destructive operations
- **Flexible**: Skip or customize any component
- **Recommended for**: First-time users

---

### **setup_flags.sh** - ⚠️ DEPRECATED / BROKEN
**STATUS**: This script is currently **DEPRECATED** and needs complete overhaul.

⚠️ **DO NOT USE** - Contains broken references and untested functionality.

**ISSUES**:
- References non-existent scripts after modularization refactor
- Flag combinations not tested since script reorganization
- Missing integration with new direct mount architecture
- Old proxy approach no longer supported

**WORKAROUND**: Use `setup_full.sh` instead (fully working and tested)

**TODO for future restoration** (estimated 60-90 minutes):
- Fix broken script references (3 missing scripts)
- Update to use new modular script structure  
- Remove/replace deprecated proxy functionality
- Test all flag combinations
- Update documentation

---

## 🎯 Recommended Workflow

### For New Users
1. **📋 [Quick Start Guide](../docs/QUICKSTART.md)** - 30-minute setup
2. **setup.sh** → Safe bootstrap preparation
3. **setup_full.sh** → Interactive guided setup

### For Advanced Users
1. **📖 [Detailed Setup Guide](../docs/SETUP.md)** - Comprehensive walkthrough
2. **setup_full.sh** → Use interactive setup (non-interactive option deprecated)
3. **⚙️ [Environment Variables](../docs/ENVIRONMENT.md)** - Configuration reference

### For Specific Tasks
- **Storage only**: See **💾 [Storage Guide](../docs/STORAGE.md)**
- **Services only**: Use `setup_full.sh` and skip unwanted sections
- **Remote access**: See **🔒 [Tailscale Guide](../docs/TAILSCALE.md)**

---

## 🔗 Related Documentation

- **📋 [Quick Start Guide](../docs/QUICKSTART.md)** - Get running in 30 minutes
- **📖 [Detailed Setup Guide](../docs/SETUP.md)** - Step-by-step comprehensive setup
- **⚙️ [Environment Variables](../docs/ENVIRONMENT.md)** - Configuration reference
- **🔧 [Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common issues and solutions


## ⚠️ setup_flags.sh Examples (DEPRECATED)

**The following examples are for reference only** - `setup_flags.sh` is currently broken.

**Instead, use `setup_full.sh` for all setup operations.**

<details>
<summary>Historical setup_flags.sh examples (for reference)</summary>

- **Full typical install (no storage rebuilds):**
  ```bash
  setup/setup_flags.sh --all  # ❌ BROKEN
  ```

- **Safe bootstrap + Docker + Immich + Media Processing:**
  ```bash
  setup/setup_flags.sh --bootstrap --colima --immich --media-processing  # ❌ BROKEN
  ```

- **Rebuild warmstore as a 2‑disk mirror (⚠️ destructive):**
  ```bash
  export SSD_DISKS="disk4 disk5"
  export RAID_I_UNDERSTAND_DATA_LOSS=1
  setup/setup_flags.sh --rebuild=warmstore --format-mount  # ❌ BROKEN
  ```

</details>

**Current working alternative**: Use `setup_full.sh` for interactive setup with all features.
