#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/diag_lib.sh"

section "Tailscale"
if command -v tailscale >/dev/null 2>&1; then
  ok "tailscale present"
  if tailscale status >/dev/null 2>&1; then ok "tailscale status OK"; else warn "tailscale status failed (run: sudo tailscale up)"; fi
  if tailscale ip -4 >/dev/null 2>&1; then ok "tailscale IP: $(tailscale ip -4)"; fi
  # Serve status (best-effort)
  if tailscale serve status >/dev/null 2>&1; then ok "tailscale serve configured"; else warn "tailscale serve not configured"; fi
else
  warn "tailscale not installed"
fi

print_summary
