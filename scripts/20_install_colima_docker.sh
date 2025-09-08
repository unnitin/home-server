#!/usr/bin/env bash
set -euo pipefail

# Do not run via sudo; brew refuses root installs
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Do not run this with sudo. Run as your user."
  exit 2
fi

# Ensure Homebrew exists
if ! command -v brew >/dev/null 2>&1; then
  echo "❌ Homebrew not found. Install from https://brew.sh and re-run."
  exit 1
fi

echo "=== Installing Colima + Docker CLI (via Homebrew) ==="

need_formula() { brew list --formula "$1" >/dev/null 2>&1 || brew install "$1"; }

need_formula colima
need_formula docker              # Docker CLI (includes Compose v2 in recent builds)
brew list --formula docker-compose >/dev/null 2>&1 || brew install docker-compose || true

echo "Colima and Docker installed."
