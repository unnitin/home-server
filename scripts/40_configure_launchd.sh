#!/usr/bin/env bash
set -euo pipefail

# Refuse root — per-user LaunchAgents only
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Run as your user (not sudo)."; exit 2
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$PLIST_DIR"

make_plist() {
  local label="$1" program="$2"; shift 2
  local plist="$PLIST_DIR/${label}.plist"
  /usr/libexec/PlistBuddy -c 'Clear dict' "$plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c 'Add :Label string '"$label" "$plist" >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments array' "$plist" >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:0 string '"$program" "$plist" >/dev/null 2>&1
  local i=1; for a in "$@"; do
    /usr/libexec/PlistBuddy -c 'Add :ProgramArguments:'"$i"' string '"$a" "$plist" >/dev/null 2>&1; i=$((i+1))
  done
  /usr/libexec/PlistBuddy -c 'Add :RunAtLoad bool true' "$plist" >/dev/null 2>&1
  /usr/libexec/PlistBuddy -c 'Add :KeepAlive bool true' "$plist" >/dev/null 2>&1
  echo "$plist"
}

bootstrap() {
  local plist="$1"
  local label; label="$(/usr/libexec/PlistBuddy -c 'Print :Label' "$plist")"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  launchctl enable "gui/$(id -u)/$label"
}

echo "=== Installing per-user launch agents ==="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Colima autostart
COLIMA_PLIST="$(make_plist io.homelab.colima /usr/bin/env bash -lc "$ROOT/scripts/21_start_colima.sh")"
bootstrap "$COLIMA_PLIST"

# Immich stack keep-alive
IMMICH_PLIST="$(make_plist io.homelab.compose.immich /usr/bin/env bash -lc "$ROOT/scripts/compose_helper.sh $ROOT/services/immich up -d")"
bootstrap "$IMMICH_PLIST"

# Optional: updater and tailscale
if [[ -x "$ROOT/scripts/80_check_updates.sh" ]]; then
  UPD_PLIST="$(make_plist io.homelab.updatecheck /usr/bin/env bash -lc "$ROOT/scripts/80_check_updates.sh")"
  bootstrap "$UPD_PLIST"
fi
if command -v tailscale >/dev/null 2>&1; then
  TS_PLIST="$(make_plist io.homelab.tailscale /usr/bin/env bash -lc "tailscale up --accept-dns=true || true")"
  bootstrap "$TS_PLIST"
fi

echo "Launch agents installed & loaded (user domain)."
