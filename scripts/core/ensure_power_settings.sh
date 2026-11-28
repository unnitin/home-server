#!/usr/bin/env bash
# scripts/ensure_power_settings.sh
# Ensure power settings remain configured (called by LaunchD service)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=environment.sh
source "${SCRIPT_DIR}/environment.sh"

# Expected power settings for headless server: the manifest's power profile
EXPECTED_SLEEP="${HOMELAB_POWER_SLEEP:-0}"
EXPECTED_DISPLAYSLEEP="${HOMELAB_POWER_DISPLAYSLEEP:-1}"
EXPECTED_DISKSLEEP="${HOMELAB_POWER_DISKSLEEP:-0}"

main() {
    echo "$(date): Checking power management settings..."

    # Get current settings
    CURRENT_SLEEP=$(pmset -g | grep "^[[:space:]]*sleep[[:space:]]" | awk '{print $2}' || echo "unknown")
    CURRENT_DISPLAYSLEEP=$(pmset -g | grep "^[[:space:]]*displaysleep[[:space:]]" | awk '{print $2}' || echo "unknown")
    CURRENT_DISKSLEEP=$(pmset -g | grep "^[[:space:]]*disksleep[[:space:]]" | awk '{print $2}' || echo "unknown")

    # Check if settings match expected values
    NEEDS_UPDATE=0

    if [[ "$CURRENT_SLEEP" != "$EXPECTED_SLEEP" ]]; then
        echo "$(date): Sleep setting incorrect: $CURRENT_SLEEP (expected: $EXPECTED_SLEEP)"
        NEEDS_UPDATE=1
    fi

    if [[ "$CURRENT_DISPLAYSLEEP" != "$EXPECTED_DISPLAYSLEEP" ]]; then
        echo "$(date): Display sleep setting incorrect: $CURRENT_DISPLAYSLEEP (expected: $EXPECTED_DISPLAYSLEEP)"
        NEEDS_UPDATE=1
    fi

    if [[ "$CURRENT_DISKSLEEP" != "$EXPECTED_DISKSLEEP" ]]; then
        echo "$(date): Disk sleep setting incorrect: $CURRENT_DISKSLEEP (expected: $EXPECTED_DISKSLEEP)"
        NEEDS_UPDATE=1
    fi

    # Apply corrections if needed
    if [[ $NEEDS_UPDATE -eq 1 ]]; then
        # Report only. Fixing needs sudo pmset, which LaunchD can't provide, and
        # core/ doesn't call infrastructure/. (The old call named a script that
        # no longer exists.)
        echo "$(date): ❌ Power settings have drifted. To restore them:"
        echo "$(date):    sudo ./scripts/infrastructure/configure_power.sh"
        return 1
    else
        echo "$(date): ✅ Power settings verified correct (sleep:$CURRENT_SLEEP, displaysleep:$CURRENT_DISPLAYSLEEP, disksleep:$CURRENT_DISKSLEEP)"
    fi

    return 0
}

# Only run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
