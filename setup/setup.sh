#!/usr/bin/env bash
set -euo pipefail

# Ensure Command Line Tools
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Command Line Tools... (a dialog may appear)"
  xcode-select --install || true
fi

# Homebrew
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

echo "Installing base CLI tools..."
brew update
brew install git jq yq coreutils gnu-sed watch htop rsync gnu-tar

echo "Bootstrap complete."
