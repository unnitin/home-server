#!/usr/bin/env bash
set -euo pipefail

# ⚠️  DEPRECATED: This script is currently BROKEN and needs overhaul
# 
# ISSUES:
# - References non-existent scripts (scripts/12_format_and_mount_raids.sh, scripts/35_install_caddy.sh, scripts/36_enable_reverse_proxy.sh)
# - Not updated after script refactoring and modularization
# - Flag combinations not tested since refactor
# - Missing integration with new direct mount architecture
#
# RECOMMENDED: Use setup_full.sh instead (fully working and tested)
#
# TODO: Complete overhaul needed (estimated 60-90 minutes work):
# - Fix broken script references
# - Update to use new modular script structure
# - Remove/replace deprecated proxy functionality
# - Test all flag combinations
# - Update documentation
#
echo "⚠️  WARNING: setup_flags.sh is DEPRECATED and may not work correctly!"
echo "📖 RECOMMENDED: Use setup/setup_full.sh instead"
echo "🔧 This script needs complete overhaul (see comments at top of file)"
echo ""
read -p "Continue anyway? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Exiting. Use setup/setup_full.sh instead."
    exit 1
fi

# --- Self-heal executable bits (safe to run even if already set) ---
_THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
_REPO_ROOT="$(cd "$_THIS_DIR/.." && pwd)"

# Ensure all scripts under setup/, scripts/, diagnostics/ are executable
find "$_REPO_ROOT/setup" "$_REPO_ROOT/scripts" "$_REPO_ROOT/diagnostics" \
  -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DO_BOOTSTRAP=0; DO_COLIMA=0; DO_IMMICH=0; DO_PLEX=0; DO_JELLYFIN=0; DO_LAUNCHD=0
DO_TS_INSTALL=0; DO_TS_UP=0; DO_TS_CONFIGURE_HTTPS=0; DO_CONFIGURE_POWER=0; DO_TS_SERVE_DIRECT=0; DO_PROXY=0; DO_LANDING=0
DO_STORAGE_MOUNTS=0; DO_REBUILD_TARGETS=""; DO_FORMAT_MOUNT=0; DRY_RUN=0

log(){ printf "[%s] %s\n" "$(date '+%F %T')" "$*"; }
run(){ if (( DRY_RUN )); then echo "DRY: $*"; else eval "$@"; fi; }

usage(){ cat <<'EOF'
setup_flags.sh — Non-interactive setup

USAGE
  setup/setup_flags.sh [OPTIONS]

OPTIONS
  --all                     bootstrap + colima + storage-mounts + immich + plex + jellyfin + launchd + tailscale-install + tailscale-up + tailscale-https + configure-power + landing
  --bootstrap               run setup/setup.sh
  --colima                  install/start Colima
  --storage-mounts          create storage mount points for services
  --immich                  deploy Immich (docker compose)
  --plex                    install native Plex
  --jellyfin                install native Jellyfin
  --launchd                 configure launchd jobs
  --tailscale-install       install tailscale
  --tailscale-up            run 'sudo tailscale up --accept-dns=true'
  --tailscale-https         configure HTTPS serving with DNS fix
  --configure-power         configure Mac mini for 24/7 server operation (prevent sleep)
  --tailscale-serve-direct  map HTTPS :443->Immich and :32400->Plex (alternative to --landing)
  --landing                 enable simple landing page with direct service access
  --enable-proxy            install Caddy and enable reverse proxy on :443
  --rebuild=<targets>       destructive rebuild of arrays (comma list: faststore,warmstore,coldstore)
  --format-mount            run scripts/12_format_and_mount_raids.sh after rebuild
  --dry-run                 print actions without executing
  -h|--help                 show help

ENVIRONMENT
  RAID_I_UNDERSTAND_DATA_LOSS=1 required for rebuilds
  SSD_DISKS / NVME_DISKS / COLD_DISKS  e.g., "disk4 disk5" or "disk4 disk5 disk6 disk7"
EOF
}

for a in "$@"; do
  case "$a" in
    --all) DO_BOOTSTRAP=1; DO_COLIMA=1; DO_STORAGE_MOUNTS=1; DO_IMMICH=1; DO_PLEX=1; DO_JELLYFIN=1; DO_LAUNCHD=1; DO_TS_INSTALL=1; DO_TS_UP=1; DO_TS_CONFIGURE_HTTPS=1; DO_CONFIGURE_POWER=1; DO_LANDING=1 ;;
    --bootstrap) DO_BOOTSTRAP=1 ;;
    --colima) DO_COLIMA=1 ;;
    --storage-mounts) DO_STORAGE_MOUNTS=1 ;;
    --immich) DO_IMMICH=1 ;;
    --plex) DO_PLEX=1 ;;
    --jellyfin) DO_JELLYFIN=1 ;;
    --launchd) DO_LAUNCHD=1 ;;
    --tailscale-install) DO_TS_INSTALL=1 ;;
    --tailscale-up) DO_TS_UP=1 ;;
    --tailscale-https) DO_TS_CONFIGURE_HTTPS=1 ;;
    --configure-power) DO_CONFIGURE_POWER=1 ;;
    --tailscale-serve-direct) DO_TS_SERVE_DIRECT=1 ;;
    --landing) DO_LANDING=1 ;;
    --enable-proxy) DO_PROXY=1 ;;
    --rebuild=*) DO_REBUILD_TARGETS="${a#*=}" ;;
    --format-mount) DO_FORMAT_MOUNT=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $a"; usage; exit 1 ;;
  esac
done

if (( DO_BOOTSTRAP )); then log "Bootstrap"; run setup/setup.sh; fi
if (( DO_COLIMA )); then log "Colima"; run scripts/infrastructure/install_docker.sh; run scripts/infrastructure/start_docker.sh; fi
if (( DO_STORAGE_MOUNTS )); then log "Storage directory structure"; run sudo scripts/storage/setup_direct_mounts.sh; fi
if (( DO_IMMICH )); then
  log "Immich"
  [[ -f services/immich/.env ]] || run bash -lc 'cd services/immich && cp -n .env.example .env || true'
  run scripts/services/deploy_containers.sh
fi
if (( DO_PLEX )); then log "Plex"; run scripts/services/install_plex.sh; fi
if (( DO_JELLYFIN )); then log "Jellyfin"; run scripts/services/install_jellyfin.sh; run scripts/services/configure_jellyfin.sh; fi

if [[ -n "$DO_REBUILD_TARGETS" ]]; then
  [[ "${RAID_I_UNDERSTAND_DATA_LOSS:-0}" == "1" ]] || { echo "Set RAID_I_UNDERSTAND_DATA_LOSS=1"; exit 2; }
  IFS=',' read -r -a targets <<< "$DO_REBUILD_TARGETS"
  for t in "${targets[@]}"; do
    case "$t" in
      warmstore) [[ -n "${SSD_DISKS:-}"  ]] || { echo "SSD_DISKS missing"; exit 3; } ;;
      faststore) [[ -n "${NVME_DISKS:-}" ]] || { echo "NVME_DISKS missing"; exit 3; } ;;
      coldstore) [[ -n "${COLD_DISKS:-}" ]] || { echo "COLD_DISKS missing"; exit 3; } ;;
      *) echo "Unknown target: $t"; exit 1 ;;
    esac
  done
  log "Rebuild: ${DO_REBUILD_TARGETS}"
  run scripts/storage/rebuild_storage.sh "${targets[@]}"
  if (( DO_FORMAT_MOUNT )); then log "Format/mount"; run scripts/storage/format_and_mount.sh; fi
fi

if (( DO_LAUNCHD )); then log "launchd"; run scripts/automation/configure_launchd.sh; fi
if (( DO_TS_INSTALL )); then log "tailscale"; run scripts/infrastructure/install_tailscale.sh; fi
if (( DO_TS_UP )); then log "tailscale up"; run sudo tailscale up --accept-dns=true; fi
if (( DO_TS_CONFIGURE_HTTPS )); then log "configure HTTPS/DNS"; run scripts/infrastructure/configure_https.sh; fi
if (( DO_CONFIGURE_POWER )); then log "configure power"; run scripts/infrastructure/configure_power.sh; fi
if (( DO_LANDING )); then log "landing page"; run scripts/services/enable_landing.sh; fi
if (( DO_TS_SERVE_DIRECT )); then
  log "tailscale serve direct"
  run sudo tailscale serve --https=443   http://localhost:2283
  run sudo tailscale serve --https=32400 http://localhost:32400
fi
if (( DO_PROXY )); then log "enable proxy"; run scripts/35_install_caddy.sh; run scripts/36_enable_reverse_proxy.sh; fi
log "Done."
