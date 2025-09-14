#!/usr/bin/env bash
# scripts/infrastructure/configure_power.sh
# Configure Mac mini for 24/7 headless server operation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_compose.sh" 2>/dev/null || true

main() {
    echo "🔧 Configuring Mac mini power management for headless server operation..."
    
    # Verify we're running with appropriate permissions
    if ! sudo -n true 2>/dev/null; then
        echo "⚠️  This script requires sudo access to modify power management settings"
        echo "💡 Run: sudo ./scripts/infrastructure/configure_power.sh"
        return 1
    fi
    
    echo ""
    echo "⚙️  Applying server-optimized power settings..."
    
    # Core sleep prevention settings
    if sudo pmset -a sleep 0 displaysleep 1 disksleep 0 2>/dev/null; then
        echo "✅ Core sleep prevention configured"
        echo "   - System sleep: disabled"
        echo "   - Display sleep: 1 minute (headless optimized)"
        echo "   - Disk sleep: disabled"
    else
        echo "❌ Failed to configure core sleep settings"
        return 1
    fi
    
    # Hibernation and power saving optimizations
    echo ""
    echo "⚙️  Configuring power saving optimizations..."
    
    # Disable hibernation on AC power
    if sudo pmset -c hibernatemode 0 2>/dev/null; then
        echo "✅ Hibernation disabled on AC power"
    else
        echo "⚠️  Could not disable hibernation"
    fi
    
    # Network wake capabilities
    if sudo pmset -a womp 1 acwake 1 ttyskeepawake 1 2>/dev/null; then
        echo "✅ Network wake capabilities enabled"
        echo "   - Wake on Magic Packet: enabled"
        echo "   - Wake on AC events: enabled"
        echo "   - Stay awake during remote sessions: enabled"
    else
        echo "⚠️  Could not configure network wake settings"
    fi
    
    # Disable power-saving features that interfere with servers
    if sudo pmset -a powernap 0 standby 0 autopoweroff 0 standbydelayhigh 0 standbydelaylow 0 2>/dev/null; then
        echo "✅ Server-interfering power features disabled"
        echo "   - Power Nap: disabled"
        echo "   - Standby mode: disabled"
        echo "   - Auto power off: disabled"
    else
        echo "⚠️  Could not disable some power-saving features"
    fi
    
    # SSD/NVMe optimizations
    if sudo pmset -a sms 0 2>/dev/null; then
        echo "✅ SSD optimizations applied"
        echo "   - Sudden Motion Sensor: disabled (not needed for SSDs)"
    else
        echo "⚠️  Could not disable Sudden Motion Sensor"
    fi
    
    echo ""
    echo "✅ Mac mini configured for 24/7 headless server operation"
    echo ""
    echo "💡 Current power management settings:"
    pmset -g | grep -E "(sleep|displaysleep|disksleep|womp|powernap|standby|sms)" | sed 's/^/   /' || true
    
    echo ""
    echo "🎯 Expected behavior:"
    echo "   • System never sleeps - services always available"
    echo "   • Display sleeps after 1 minute (saves power, no display connected)"
    echo "   • Disks stay active - no spin-up delays"
    echo "   • Remote wake enabled - can wake system if needed"
    echo "   • Optimized for SSD/NVMe storage"
    
    return 0
}

# Only run if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
