#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "launchd jobs (current user)"
labels=(
  "io.homelab.colima"
  "io.homelab.immich"
  "io.homelab.updatecheck"
  "io.homelab.tailscale"
)
for lbl in "${labels[@]}"; do
  if launchctl list | grep -q "$lbl"; then ok "Loaded: $lbl"; else warn "Not loaded: $lbl"; fi
done

print_summary
