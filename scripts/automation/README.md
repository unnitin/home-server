# 🤖 Automation Module

Automation layer managing LaunchD services, scheduled tasks, system monitoring, and maintenance.

## 📋 Scripts

### **Service Management**

#### **configure_launchd.sh**
**Purpose**: Install comprehensive recovery automation using LaunchD  
**Usage**: `./scripts/automation/configure_launchd.sh [--render-only] [JOB...]` (default: every job; `TEST_MODE=1` also renders only)  
**Features**: The jobs and their order come from the manifest's boot order. A job held with `launchctl disable` is rendered but stays held. Refuses to load jobs from a linked git worktree (they'd break when it's removed; `HOMELAB_ALLOW_WORKTREE=1` overrides)  
**Placeholders**: `__REPO__` (this checkout, wherever it lives), `__HOME__`, `__USER__`. A plist with an unfilled placeholder is refused
**Preview**: `TEST_MODE=1 LAUNCHD_PLIST_DIR=/tmp/plists scripts/automation/configure_launchd.sh` (or `--render-only`) renders without loading anything
**Note**: Don't run the jobs from a checkout under `~/Documents`. macOS blocks LaunchD jobs from executing scripts there (exit 126); see D19 in `docs/mcp-refactor/01-assessment.md`

### **System Monitoring**

#### **check_updates.sh**
**Purpose**: Report available updates (report only: nothing is upgraded, pulled or restarted)
**Usage**: Run nightly at 03:00 by LaunchD `io.homelab.updatecheck`; output in `/tmp/homelab-updatecheck.out`
**Features**: Outdated Homebrew packages; running Immich version vs. the latest release, with a release-notes link
**Note**: `--apply` is refused until Phase 5 adds version pinning, a database backup and approval. Unattended Immich upgrades can break the library

### **Media Automation Setup**

#### **setup_media_processing.sh**
**Purpose**: Set up media processing: the staging folders, the optional tools, and the media watcher's LaunchD job  
**Usage**: `./scripts/automation/setup_media_processing.sh`  
**Features**: Refuses unless the media tier is really mounted; folders via `setup_direct_mounts.sh` (the manifest's layout), the job via `configure_launchd.sh media.watcher`. No sudo, no recursive chmod or chown

## 🔗 Module Dependencies

**Depends on**: `core/`, `storage/`, `infrastructure/`, `services/`  
**Used by**: LaunchD services, manual maintenance

## 📁 Module Architecture

```
scripts/automation/
├── configure_launchd.sh         # LaunchD service setup
├── check_updates.sh            # Update monitoring
├── setup_media_processing.sh   # Media automation setup
└── README.md                   # This documentation
```

---

**📖 For complete script documentation**: → [**🛠️ Scripts Reference**](../README.md)
