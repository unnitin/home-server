#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/check_raid_status.sh"
"$DIR/check_plex_native.sh"
"$DIR/check_docker_services.sh"
"$DIR/network_port_check.sh" localhost 2283
"$DIR/verify_media_paths.sh"
