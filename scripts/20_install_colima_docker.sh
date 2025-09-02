#!/usr/bin/env bash
set -euo pipefail
eval "$(/opt/homebrew/bin/brew shellenv)" || true
brew install colima docker docker-compose
