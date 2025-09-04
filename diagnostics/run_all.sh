#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
ret=0
for s in \
  check_prereqs.sh \
  check_homebrew.sh \
  check_colima_docker.sh \
  check_storage.sh \
  check_immich.sh \
  check_plex_native.sh \
  check_tailscale.sh \
  check_reverse_proxy.sh \
  check_launchd.sh
do
  echo -e "\n==================== $s ===================="
  if ! "$BASE/$s"; then
    echo ">>> $s reported issues"
    ret=1
  fi
done
exit $ret
