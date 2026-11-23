#!/usr/bin/env bash
# diagnostics/check_power_settings.sh
# Check Mac mini power management settings for 24/7 server operation

set -euo pipefail

# Expected values for headless server operation
EXPECTED_SLEEP=0
EXPECTED_DISPLAYSLEEP=1
EXPECTED_DISKSLEEP=0
EXPECTED_WOMP=1
EXPECTED_POWERNAP=0
EXPECTED_STANDBY=0

# Colors for output (off when NO_COLOR is set or stdout isn't a terminal, as in diag_lib.sh)
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
fi

check_passed=0
check_failed=0
check_warnings=0

print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}✅ PASS${NC} - $message"
            ((check_passed++))
            ;;
        "FAIL")
            echo -e "${RED}❌ FAIL${NC} - $message"
            ((check_failed++))
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  WARN${NC} - $message"
            ((check_warnings++))
            ;;
    esac
}

get_power_setting() {
    local setting=$1
    pmset -g | grep "^[[:space:]]*${setting}[[:space:]]" | awk '{print $2}' | head -1
}

echo "🔍 Mac Mini HomeServer - Power Management Diagnostics"
echo "======================================================="
echo ""

# Check if pmset is available
if ! command -v pmset &> /dev/null; then
    print_status "FAIL" "pmset command not found - cannot check power settings"
    exit 1
fi

echo "📊 Current Power Settings:"
echo "========================="
pmset -g | grep -E "(sleep|displaysleep|disksleep|womp|powernap|standby|sms)" | sed 's/^/   /' || true
echo ""

echo "🔍 Power Management Validation:"
echo "==============================="

# Check system sleep
current_sleep=$(get_power_setting "sleep")
if [[ "$current_sleep" == "$EXPECTED_SLEEP" ]]; then
    print_status "PASS" "System sleep disabled (sleep=$current_sleep) - 24/7 availability ensured"
else
    print_status "FAIL" "System sleep not disabled (sleep=$current_sleep, expected: $EXPECTED_SLEEP)"
    echo "   💡 Fix: sudo pmset -a sleep 0"
fi

# Check display sleep
current_displaysleep=$(get_power_setting "displaysleep")
if [[ "$current_displaysleep" == "$EXPECTED_DISPLAYSLEEP" ]]; then
    print_status "PASS" "Display sleep optimized (displaysleep=$current_displaysleep) - headless configuration"
else
    if [[ "$current_displaysleep" == "0" ]]; then
        print_status "WARN" "Display sleep disabled (displaysleep=$current_displaysleep) - slightly higher power usage"
        echo "   💡 Consider: sudo pmset -a displaysleep 1 (saves power, no display connected)"
    else
        print_status "WARN" "Display sleep longer than optimal (displaysleep=$current_displaysleep, recommended: $EXPECTED_DISPLAYSLEEP)"
        echo "   💡 Consider: sudo pmset -a displaysleep 1"
    fi
fi

# Check disk sleep
current_disksleep=$(get_power_setting "disksleep")
if [[ "$current_disksleep" == "$EXPECTED_DISKSLEEP" ]]; then
    print_status "PASS" "Disk sleep disabled (disksleep=$current_disksleep) - immediate media access"
else
    print_status "FAIL" "Disk sleep enabled (disksleep=$current_disksleep, expected: $EXPECTED_DISKSLEEP)"
    echo "   💡 Fix: sudo pmset -a disksleep 0"
fi

# Check wake on magic packet
current_womp=$(get_power_setting "womp")
if [[ "$current_womp" == "$EXPECTED_WOMP" ]]; then
    print_status "PASS" "Wake on Magic Packet enabled (womp=$current_womp) - remote wake capability"
else
    print_status "WARN" "Wake on Magic Packet disabled (womp=$current_womp, recommended: $EXPECTED_WOMP)"
    echo "   💡 Consider: sudo pmset -a womp 1"
fi

# Check Power Nap
current_powernap=$(get_power_setting "powernap")
if [[ "$current_powernap" == "$EXPECTED_POWERNAP" ]]; then
    print_status "PASS" "Power Nap disabled (powernap=$current_powernap) - no interference with services"
else
    print_status "WARN" "Power Nap enabled (powernap=$current_powernap, recommended: $EXPECTED_POWERNAP)"
    echo "   💡 Consider: sudo pmset -a powernap 0"
fi

# Check standby mode
current_standby=$(get_power_setting "standby")
if [[ "$current_standby" == "$EXPECTED_STANDBY" ]]; then
    print_status "PASS" "Standby mode disabled (standby=$current_standby) - prevents deep sleep"
else
    print_status "WARN" "Standby mode enabled (standby=$current_standby, recommended: $EXPECTED_STANDBY)"
    echo "   💡 Consider: sudo pmset -a standby 0"
fi

# Check for sleep assertions (what's keeping system awake)
echo ""
echo "🔍 Current Sleep Assertions:"
echo "============================"
sleep_assertions=$(pmset -g assertions | grep -E "(PreventSystemSleep|PreventUserIdleSystemSleep)" | head -5)
if [[ -n "$sleep_assertions" ]]; then
    echo "$sleep_assertions" | sed 's/^/   /'
else
    echo "   No active sleep prevention assertions found"
fi

# Check power source
echo ""
echo "⚡ Power Source Information:"
echo "==========================="
power_source=$(pmset -g ps | head -2 | tail -1)
echo "   $power_source"

if echo "$power_source" | grep -q "AC Power"; then
    print_status "PASS" "Running on AC power - optimal for server operation"
elif echo "$power_source" | grep -q "Battery Power"; then
    print_status "WARN" "Running on battery power - not ideal for 24/7 server"
    echo "   💡 Connect to AC power for reliable server operation"
fi

# Check for SSD optimizations
echo ""
echo "💾 Storage Optimizations:"
echo "========================"
current_sms=$(get_power_setting "sms")
if [[ "$current_sms" == "0" ]]; then
    print_status "PASS" "Sudden Motion Sensor disabled (sms=0) - optimized for SSD/NVMe"
elif [[ -n "$current_sms" ]]; then
    print_status "WARN" "Sudden Motion Sensor enabled (sms=$current_sms) - unnecessary for SSDs"
    echo "   💡 Consider: sudo pmset -a sms 0"
else
    echo "   ℹ️  Sudden Motion Sensor setting not available on this system"
fi

# Summary
echo ""
echo "📊 Power Management Summary:"
echo "==========================="
echo "   ✅ Passed: $check_passed checks"
if [[ $check_warnings -gt 0 ]]; then
    echo "   ⚠️  Warnings: $check_warnings (optional optimizations)"
fi
if [[ $check_failed -gt 0 ]]; then
    echo "   ❌ Failed: $check_failed (requires attention)"
fi

echo ""

# Overall status
if [[ $check_failed -eq 0 ]]; then
    if [[ $check_warnings -eq 0 ]]; then
        echo -e "${GREEN}🎉 EXCELLENT${NC} - Power management optimally configured for 24/7 server operation"
        exit_code=0
    else
        echo -e "${YELLOW}✅ GOOD${NC} - Core power management configured, minor optimizations available"
        exit_code=0
    fi
else
    echo -e "${RED}🚨 ATTENTION NEEDED${NC} - Critical power settings require configuration"
    echo ""
    echo "🔧 Quick fix command:"
    echo "   sudo ./scripts/92_configure_power.sh"
    exit_code=1
fi

echo ""
echo "💡 For complete power management setup:"
echo "   sudo ./scripts/92_configure_power.sh"
echo ""
echo "🔍 To monitor power settings:"
echo "   pmset -g"
echo "   tail -f /tmp/powermgmt.out"

exit $exit_code
