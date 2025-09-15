#!/usr/bin/env bash
# Setup service access symlinks for three-tier storage architecture.
# Creates logical access points for applications while keeping data on appropriate storage tiers.

set -euo pipefail

echo "=== Setting up Service Access Symlinks ==="

# Function to create symlink if target exists
create_symlink() {
  local symlink_path="$1"
  local target_path="$2"
  local description="$3"
  
  if [[ -d "$target_path" ]]; then
    if [[ -L "$symlink_path" ]]; then
      echo "   Updating existing symlink: $symlink_path -> $target_path"
      sudo rm "$symlink_path"
    elif [[ -d "$symlink_path" ]]; then
      echo "   Removing existing directory: $symlink_path"
      sudo rm -rf "$symlink_path"
    fi
    
    sudo ln -sf "$target_path" "$symlink_path"
    echo "   ✅ $description: $symlink_path -> $target_path"
  else
    echo "   ⚠️  Target not found: $target_path (skipping $description)"
  fi
}

# Service access symlinks
echo "Creating service access symlinks..."

# Photos access (for Immich)
create_symlink "/Volumes/Photos" "/Volumes/faststore/photos" "Photos access"

# Media access (for Plex and other services)
create_symlink "/Volumes/Media" "/Volumes/warmstore" "Media access"

# Archive access (for future coldstore)
create_symlink "/Volumes/Archive" "/Volumes/coldstore" "Archive access"

echo
echo "=== Verifying Symlinks ==="
for symlink in "/Volumes/Photos" "/Volumes/Media" "/Volumes/Archive"; do
  if [[ -L "$symlink" ]]; then
    target=$(readlink "$symlink")
    echo "✅ $symlink -> $target"
  else
    echo "❌ $symlink (not a symlink or doesn't exist)"
  fi
done

echo
echo "✅ Service access symlinks setup complete!"
