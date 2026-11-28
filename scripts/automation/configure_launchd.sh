#!/usr/bin/env bash
set -euo pipefail

# Refuse root — per-user LaunchAgents only
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Run as your user (not sudo)."; exit 2
fi

# Usage: configure_launchd.sh [--render-only] [JOB...]
#   JOB: a job from the manifest's boot order (e.g. media.watcher); default: all.
# TEST_MODE=1 or --render-only: render plists into LAUNCHD_PLIST_DIR and stop;
# nothing is loaded, unloaded or restarted.
# A job held with `launchctl disable` stays held: it is rendered, not loaded.
RENDER_ONLY=false
if [[ "${TEST_MODE:-0}" == "1" ]]; then
  RENDER_ONLY=true
fi
if [[ "${1:-}" == "--render-only" ]]; then
  RENDER_ONLY=true
  shift
fi

PLIST_DIR="${LAUNCHD_PLIST_DIR:-$HOME/Library/LaunchAgents}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"
TEMPLATE_DIR="$ROOT/launchd"
# shellcheck source=../core/environment.sh
source "$ROOT/scripts/core/environment.sh"

# A linked git worktree comes and goes (feature branches are deleted after merging),
# so jobs loaded from one break when it does. Load from the main checkout.
if ! $RENDER_ONLY && [[ "${HOMELAB_ALLOW_WORKTREE:-0}" != "1" ]] &&
    [[ "$(git -C "$ROOT" rev-parse --git-dir 2>/dev/null)" != "$(git -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" ]]; then
  echo "❌ $ROOT is a linked git worktree: jobs loaded from it break when it's removed."
  echo "   Run this from the main checkout, or set HOMELAB_ALLOW_WORKTREE=1 (or use --render-only)."
  exit 2
fi

if [[ "$ROOT" == "$HOME/Documents/"* ]] && ! $RENDER_ONLY; then
  echo "⚠️  The repo is under ~/Documents. macOS blocks LaunchD jobs from running scripts there"
  echo "   (exit 126, 'Operation not permitted'). Move it first, e.g. to ~/home-server."
  echo "   See D19 in docs/mcp-refactor/01-assessment.md."
fi

mkdir -p "$PLIST_DIR"

# Install plist from template with variable substitution
install_plist() {
  local service_name="$1"
  local template_plist="$TEMPLATE_DIR/io.homelab.${service_name}.plist"
  local target_plist="$PLIST_DIR/io.homelab.${service_name}.plist"

  echo "📦 Installing service: io.homelab.${service_name}"

  # Check if template exists
  if [[ ! -f "$template_plist" ]]; then
    echo "⚠️  Template not found: $template_plist"
    return 1
  fi

  # Copy template and substitute variables
  cp "$template_plist" "$target_plist"

  # Replace template variables (__REPO__ = this checkout, wherever it lives)
  sed -i '' "s|__REPO__|$ROOT|g" "$target_plist"
  sed -i '' "s|__HOME__|$HOME|g" "$target_plist"
  sed -i '' "s|__USER__|$(whoami)|g" "$target_plist"

  # Refuse a half-rendered plist (an unfilled __REPO__ is what broke updatecheck)
  if grep -qE '__[A-Z]+__' "$target_plist"; then
    echo "❌ Unfilled placeholder in $target_plist: $(grep -oE '__[A-Z]+__' "$target_plist" | sort -u | tr '\n' ' ')"
    return 1
  fi
  if ! plutil -lint -s "$target_plist"; then
    echo "❌ Rendered plist is invalid: $target_plist"
    return 1
  fi

  echo "   ✅ Template processed: $target_plist"
  return 0
}

# Bootstrap (load and enable) a LaunchD service
bootstrap() {
  local service_name="$1"
  local plist="$PLIST_DIR/io.homelab.${service_name}.plist"
  local label="io.homelab.${service_name}"

  if $RENDER_ONLY; then
    echo "   ⏭️  Render only: $label not loaded"
    return 0
  fi

  # Held on purpose (launchctl disable): leave it held
  if launchctl print-disabled "gui/$(id -u)" 2>/dev/null | grep -qE "\"$label\" => (disabled|true)"; then
    echo "   ⏸️  Held: $label is disabled, so it was rendered but not loaded"
    echo "      To release it: launchctl enable gui/$(id -u)/$label, then run this again"
    HELD=$((HELD + 1))
    return 0
  fi

  echo "🚀 Bootstrapping service: $label"

  # Unload existing service (ignore errors)
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true

  # Load and enable new service
  if launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null; then
    if launchctl enable "gui/$(id -u)/$label" 2>/dev/null; then
      echo "   ✅ Service active: $label"
    else
      echo "   ⚠️  Enable failed: $label"
    fi
  else
    echo "   ❌ Bootstrap failed: $label"
  fi
}

echo "=== Installing Enhanced Recovery Automation ==="
echo "📁 Templates: $TEMPLATE_DIR"
echo "🎯 Target: $PLIST_DIR"
echo ""

# Every job in the manifest's boot order (config/homelab.yaml), or the ones named
read -r -a ALL_SERVICES <<<"$HOMELAB_LAUNCHD_SERVICES"
if (($#)); then
  for service in "$@"; do
    if [[ " $HOMELAB_LAUNCHD_SERVICES " != *" $service "* ]]; then
      echo "❌ Unknown job: $service (known: $HOMELAB_LAUNCHD_SERVICES)"; exit 2
    fi
  done
  SERVICES=("$@")
else
  SERVICES=("${ALL_SERVICES[@]}")
fi

# Install and bootstrap each service
INSTALLED=0
FAILED=0
HELD=0

for service in "${SERVICES[@]}"; do
  echo "--- Processing: $service ---"

  # io.homelab.tailscale runs Homebrew's tailscaled. When Tailscale is the Mac app,
  # the app runs its own daemon and this job would only crash-loop.
  if [[ "$service" == "tailscale" && ! -x /opt/homebrew/sbin/tailscaled ]]; then
    echo "   ⏭️  Skipping: no Homebrew tailscaled (the Tailscale app manages its own daemon)"
    echo ""
    continue
  fi

  if install_plist "$service"; then
    if bootstrap "$service"; then
      INSTALLED=$((INSTALLED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
  else
    echo "   ⚠️  Skipping bootstrap (template missing or invalid)"
    FAILED=$((FAILED + 1))
  fi
  echo ""
done

echo "=== Installation Complete ==="
echo "✅ Successfully installed: $INSTALLED services"
echo "❌ Failed installations: $FAILED services"
if ((HELD)); then
  echo "⏸️  Held (rendered, not loaded): $HELD services"
fi
echo ""

if [[ $INSTALLED -gt 0 ]]; then
  echo "📋 View service status:"
  echo "   launchctl list | grep homelab"
  echo ""
  echo "📄 Monitor logs during restart:"
  echo "   tail -f /tmp/homelab-*.{out,err}"
  echo ""
  echo "🔄 Enhanced automation ready for graceful recovery!"
else
  echo "⚠️  No services were successfully installed."
  exit 1
fi
