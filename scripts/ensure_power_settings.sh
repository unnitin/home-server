#!/usr/bin/env bash
# scripts/ensure_power_settings.sh
# Ensure power settings remain configured (called by LaunchD service)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Expected power settings for headless server
EXPECTED_SLEEP=0
EXPECTED_DISPLAYSLEEP=1
EXPECTED_DISKSLEEP=0

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
        echo "$(date): Power settings have changed, reapplying server configuration..."
        
        if "$SCRIPT_DIR/92_configure_power.sh" >/dev/null 2>&1; then
            echo "$(date): ✅ Power settings successfully restored"
        else
            echo "$(date): ❌ Failed to restore power settings - manual intervention required"
            echo "$(date): Manual command: sudo $SCRIPT_DIR/92_configure_power.sh"
            return 1
        fi
    else
        echo "$(date): ✅ Power settings verified correct (sleep:$CURRENT_SLEEP, displaysleep:$CURRENT_DISPLAYSLEEP, disksleep:$CURRENT_DISKSLEEP)"
    fi
    
    return 0
}

# Only run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
