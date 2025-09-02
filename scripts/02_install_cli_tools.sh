#!/usr/bin/env bash
set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)" || true
brew install jq yq coreutils smartmontools colima docker docker-compose watch
echo "CLI tools installed."
