#!/usr/bin/env bash
# Storage usage for every tier in the manifest (config/homelab.yaml), against
# each tier's own warn and crit thresholds.
#
# Usage: ./scripts/core/check_storage_usage.sh
# Exit:  0 = every mounted tier below its warn threshold
#        1 = at least one mounted tier at or above warn (or crit)
#
# A tier counts only when diskutil says a volume is mounted there. An empty
# mount-point folder isn't storage: df would report the internal disk (D22).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=environment.sh
source "${SCRIPT_DIR}/environment.sh"

echo "Home server storage usage"
echo "========================="
echo ""

high=0
for tier in $HOMELAB_TIERS; do
    upper=$(printf '%s' "$tier" | tr '[:lower:]' '[:upper:]')
    use_var="HOMELAB_TIER_${upper}_USE"
    warn_var="HOMELAB_TIER_${upper}_WARN_PCT"
    crit_var="HOMELAB_TIER_${upper}_CRIT_PCT"
    mount=$(homelab_tier_mount "$tier")
    warn="${!warn_var}"
    crit="${!crit_var}"

    echo "$tier ($mount): ${!use_var}"
    if ! homelab_is_mounted "$mount"; then
        echo "  Not mounted"
        echo ""
        continue
    fi

    # df -P: one line per filesystem in a fixed format; -h for readable sizes
    used_pct=$(df -P "$mount" | awk 'NR == 2 { sub("%", "", $5); print $5 }')
    read -r size used avail < <(df -h "$mount" | awk 'NR == 2 { print $2, $3, $4 }')
    echo "  Size: $size | Used: $used | Available: $avail | Usage: ${used_pct}%"
    if (( used_pct >= crit )); then
        echo "  Status: CRITICAL (at or above ${crit}%)"
        high=1
    elif (( used_pct >= warn )); then
        echo "  Status: WARNING (at or above ${warn}%)"
        high=1
    else
        echo "  Status: OK (warns at ${warn}%)"
    fi
    echo ""
done

if (( high )); then
    echo "Storage usage is high: clean up or expand the tiers marked above."
else
    echo "Storage usage is within limits on every mounted tier."
fi
exit "$high"
