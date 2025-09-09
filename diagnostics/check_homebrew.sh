#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "brew present: $(brew --version | head -n1)"
  if brew doctor >/dev/null 2>&1; then ok "brew doctor OK"; else warn "brew doctor reported issues (run manually to inspect)"; fi
  # Common prefix
  if [ -d /opt/homebrew ]; then
    if [ -w /opt/homebrew ]; then ok "/opt/homebrew writable"; else warn "/opt/homebrew not writable; may need: sudo chown -R $(whoami) /opt/homebrew"; fi
  fi
else
  fail "brew not installed. Run setup/setup.sh to install Homebrew."
fi

print_summary
