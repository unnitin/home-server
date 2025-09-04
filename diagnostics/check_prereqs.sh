#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Shell & Tooling"
ok "Bash version: $BASH_VERSION"
require_cmd xattr || true
require_cmd git || true
require_cmd python3 || true

section "Gatekeeper quarantine"
if xattr -p com.apple.quarantine . >/dev/null 2>&1; then
  warn "Quarantine flags detected in repo. Run: xattr -dr com.apple.quarantine ."
else
  ok "No quarantine flags on repo root"
fi

section "Xcode CLT (needed for Homebrew)"
if xcode-select -p >/dev/null 2>&1; then ok "xcode-select present"; else warn "xcode-select missing. Run: xcode-select --install"; fi

print_summary
