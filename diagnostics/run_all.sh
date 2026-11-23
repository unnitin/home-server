#!/usr/bin/env bash
set -euo pipefail

# Comprehensive diagnostics runner for Mac Mini HomeServer
# Runs all diagnostic checks and provides a summary

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/diag_lib.sh"

echo "🔍 Hakuna Mateti HomeServer - Comprehensive Diagnostics"
echo "========================================================"
date
echo

# Array to track individual script results
SCRIPT_RESULTS=()

run_diagnostic() {
    local script="$1"
    local description="$2"

    echo -e "\n${YELLOW}🔸 $description${NC}"
    echo "----------------------------------------"

    # Always returns 0: a failing check is recorded, never allowed to abort the
    # sweep (under `set -e` that used to skip every later check and the summary).
    if [[ -x "$SCRIPT_DIR/$script" ]]; then
        if "$SCRIPT_DIR/$script"; then
            SCRIPT_RESULTS+=("✅ $description")
        else
            SCRIPT_RESULTS+=("❌ $description")
        fi
    else
        warn "Script not found or not executable: $script"
        SCRIPT_RESULTS+=("⚠️  $description (script missing)")
    fi
    return 0
}

# Core System Checks
section "Core System Health"
run_diagnostic "check_prereqs.sh" "Prerequisites & Dependencies"
run_diagnostic "check_homebrew.sh" "Homebrew Package Manager"

# Storage & RAID Checks
section "Storage & RAID"
run_diagnostic "check_raid_status.sh" "RAID Array Status"
run_diagnostic "check_storage.sh" "Storage Health"
run_diagnostic "verify_media_paths.sh" "Mount Points & Paths"

# Container & Runtime Checks
section "Docker & Containers"
run_diagnostic "check_colima_docker.sh" "Colima & Docker Runtime"
run_diagnostic "check_docker_services.sh" "Docker Compose Services"

# Service Checks
section "Application Services"
run_diagnostic "check_immich.sh" "Immich Photo Service"
run_diagnostic "check_plex_native.sh" "Plex Media Server"
run_diagnostic "check_jellyfin.sh" "Jellyfin Media Server"

# Network & Remote Access
section "Network & Remote Access"
run_diagnostic "check_tailscale.sh" "Tailscale VPN"
run_diagnostic "check_remote_access.sh" "Remote Access (tailscale serve)"

# System Integration
section "System Integration"
run_diagnostic "check_launchd.sh" "LaunchD Services"
run_diagnostic "check_power_settings.sh" "Power Management Settings"

# Network Connectivity Tests
section "Network Connectivity"
echo "Testing critical service ports..."
"$SCRIPT_DIR/network_port_check.sh" localhost 2283 || true   # Immich
"$SCRIPT_DIR/network_port_check.sh" localhost 32400 || true  # Plex
"$SCRIPT_DIR/network_port_check.sh" localhost 8096 || true   # Jellyfin

# Final Summary
echo -e "\n${YELLOW}📊 DIAGNOSTIC SUMMARY${NC}"
echo "========================================================"
echo "Completed: $(date)"
echo

passed=0
failed=0
warnings=0

for result in "${SCRIPT_RESULTS[@]}"; do
    echo "$result"
    if [[ $result == ✅* ]]; then
        passed=$((passed + 1))
    elif [[ $result == ❌* ]]; then
        failed=$((failed + 1))
    else
        warnings=$((warnings + 1))
    fi
done

echo
echo "Results: $passed passed, $warnings warnings, $failed failed"

# Overall health assessment
if ((failed == 0 && warnings == 0)); then
    echo -e "${GREEN}🎉 All systems healthy!${NC}"
    exit 0
elif ((failed == 0)); then
    echo -e "${YELLOW}⚠️  System mostly healthy with minor warnings${NC}"
    exit 0
else
    echo -e "${RED}🚨 Issues found - check failed components${NC}"
    echo -e "\n💡 For troubleshooting help:"
    echo "   ./docs/TROUBLESHOOTING.md"
    echo "   ./diagnostics/collect_logs.sh"
    exit 1
fi
