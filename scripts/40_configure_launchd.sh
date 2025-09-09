#!/usr/bin/env bash
set -euo pipefail

# Refuse to run as root — use per-user LaunchAgents
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Do not run this as root. Run as your user so we install LaunchAgents." >&2
  exit 2
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR"

make_plist() {
  local label="$1" program="$2"; shift 2
  local plist="$PLIST_DIR/${label}.plist"
  /usr/libexec/PlistBuddy -c 'Clear dict' "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c 'Add :Label string '"$label" "$plist"
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string '"$program" "$plist"
  local i=1
  for a in "$@"; do
    /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:'"$i"' string '"$a" "$plist"; i=$((i+1))
  done
  /usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$plist"
  /usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "$plist"
  echo "$plist"
}

bootstrap() {
  local plist="$1" label
  label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")"
  # Unload if already loaded, then (re)load
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  launchctl enable "gui/$(id -u)/$label"
}

echo "=== Installing per-user launch agents ==="

# Colima (ensures Docker daemon is up for 'docker context colima')
COLIMA_PLIST="$(make_plist io.homelab.colima /usr/local/bin/bash -lc "$HOME/scripts/21_start_colima.sh")"
bootstrap "$COLIMA_PLIST"

# Immich compose (keeps stack up after reboots)
IMMICH_PLIST="$(make_plist io.homelab.compose.immich /usr/local/bin/bash -lc "$HOME/scripts/compose_helper.sh $HOME/services/immich up -d")"
bootstrap "$IMMICH_PLIST"

# Update checker (optional; no-op if script missing)
if [[ -x "$HOME/scripts/80_update_check.sh" ]]; then
  UPD_PLIST="$(make_plist io.homelab.updatecheck /usr/local/bin/bash -lc "$HOME/scripts/80_update_check.sh")"
  bootstrap "$UPD_PLIST"
fi

# Tailscale auto-start (if desired; expects you’ve already authenticated once)
if command -v tailscale >/dev/null 2>&1; then
  TS_PLIST="$(make_plist io.homelab.tailscale /usr/local/bin/bash -lc "tailscale up --accept-dns=true || true")"
  bootstrap "$TS_PLIST"
fi

echo "Launch agents installed & loaded (user domain)."
