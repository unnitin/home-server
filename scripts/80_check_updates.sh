#!/usr/bin/env bash
# Homeserver update checker / updater
# - Checks for Homebrew (formulae + casks) updates
# - Checks for Docker image updates (Immich stack)
# - Checks Plex native app updates (via Homebrew cask)
# - Optionally applies updates with --apply
#
# Logging: write all output to stdout; when run via launchd plist, logs go to /var/log/homeserver-updatecheck.{out,err}.log
#
set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

log() { printf "[%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# Ensure Homebrew in PATH for non-interactive shells
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

log "== Update check started (apply=$APPLY) =="

# --- Homebrew updates (formulae + casks, including Plex Media Server) ---
if command -v brew >/dev/null 2>&1; then
  log "-- Homebrew: updating taps --"
  brew update || true

  log "-- Homebrew: outdated formulae --"
  brew outdated || true

  log "-- Homebrew: outdated casks --"
  brew outdated --cask || true

  if (( APPLY )); then
    log "-- Homebrew: upgrading formulae --"
    brew upgrade || true

    log "-- Homebrew: upgrading casks (including Plex) --"
    # Use --greedy to catch casks that don't auto-bump version numbers (plex sometimes uses auto-updater)
    brew upgrade --cask --greedy || true

    log "-- Homebrew: cleanup --"
    brew cleanup || true
  fi
else
  log "Homebrew not found; skipping brew checks."
fi

# --- Docker images (Immich stack) ---
if command -v docker >/dev/null 2>&1; then
  log "-- Docker: checking image freshness (immich + deps) --"
  images=(
    "ghcr.io/immich-app/immich-server:release"
    "ghcr.io/immich-app/immich-machine-learning:release"
    "redis:7-alpine"
    "postgres:15-alpine"
  )
  for img in "${images[@]}"; do
    log "Pulling: $img"
    docker pull "$img" || true
  done

  if (( APPLY )); then
    # Recreate Immich services if there are new images
    if [[ -d "$(pwd)/services/immich" ]]; then
      log "-- Docker Compose: recreating Immich (if needed) --"
      ( cd services/immich && docker compose up -d )
    else
      log "Immich compose directory not found; skipping compose up."
    fi
  fi

  # List dangling images if any (informational)
  log "-- Docker: dangling images --"
  docker images -f "dangling=true" || true

  if (( APPLY )); then
    log "-- Docker: pruning unused images (safe) --"
    docker image prune -f || true
  fi
else
  log "Docker not found; skipping docker checks."
fi

log "== Update check complete =="
