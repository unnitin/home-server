#!/usr/bin/env bash
# Shared configuration for every module (D12). Source it; don't run it:
#
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../core/environment.sh"
#
# Sets HOMELAB_REPO (this checkout, wherever it lives) and every HOMELAB_* value
# in config/homelab.env, which is generated from the manifest, config/homelab.yaml
# (python3 -m homelab config render). Then config/homelab.local.env, the
# per-machine overrides, if it exists. Every value is exported.
#
# A HOMELAB_* variable already set in the environment wins over both files, so a
# test or a one-off run can point a script elsewhere:
#   HOMELAB_MEDIA_ROOT=/tmp/media ./scripts/media/processor.sh
#
# Reading the values needs no Python: the generated file is committed.

set -euo pipefail

# Physical path (-P): a checkout reached through a symlink in ~/Documents would
# otherwise be recorded under ~/Documents, which LaunchD jobs can't run from (D19).
HOMELAB_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export HOMELAB_REPO

_homelab_load_env() {
    local env_file="$HOMELAB_REPO/config/homelab.env"
    local local_file="$HOMELAB_REPO/config/homelab.local.env"
    local saved=() name kv

    if [[ ! -f "$env_file" ]]; then
        echo "environment.sh: $env_file is missing (python3 -m homelab config render)" >&2
        return 1
    fi

    # Values the caller set win: remember them, load the files, put them back.
    while IFS= read -r name; do
        [[ "$name" == HOMELAB_REPO ]] && continue
        saved+=("$name=${!name}")
    done < <(compgen -v | grep '^HOMELAB_' || true)

    set -a
    # shellcheck source=../../config/homelab.env
    source "$env_file"
    if [[ -f "$local_file" ]]; then
        # shellcheck disable=SC1090
        source "$local_file"
    fi
    set +a

    for kv in ${saved[@]+"${saved[@]}"}; do
        export "${kv%%=*}=${kv#*=}"
    done
}
_homelab_load_env

# The mount point of a storage tier: homelab_tier_mount warmstore
homelab_tier_mount() {
    local var
    var="HOMELAB_TIER_$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')_MOUNT"
    if [[ -z "${1:-}" || -z "${!var:-}" ]]; then
        echo "homelab_tier_mount: unknown tier '${1:-}' (known: $HOMELAB_TIERS)" >&2
        return 1
    fi
    printf '%s\n' "${!var}"
}
