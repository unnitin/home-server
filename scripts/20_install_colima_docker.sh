#!/usr/bin/env bash
set -euo pipefail

# Never run this via sudo: Homebrew refuses root installs and it breaks $HOME ownership.
if [[ ${EUID:-0} -eq 0 ]]; then
  echo "❌ Do not run this script with sudo. Run as your user; it will sudo only where needed."
  exit 2
fi

# Ensure Homebrew exists
if ! command -v brew >/dev/null 2>&1; then
  echo "❌ Homebrew not found. Install from https://brew.sh and re-run."
  exit 1
fi

echo "=== Installing Colima + Docker CLI (via Homebrew) ==="

# Formulas we actually need
need_formula() { brew list --formula "$1" >/dev/null 2>&1 || brew install "$1"; }

need_formula colima
need_formula docker          # Docker CLI
# Compose v2 is bundled with recent Docker; still install the plugin explicitly for safety:
brew list --formula docker-compose >/dev/null 2>&1 || brew install docker-compose || true

echo "Colima and Docker installed."
