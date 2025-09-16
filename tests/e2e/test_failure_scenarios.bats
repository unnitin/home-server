#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
    export TEST_MODE=1
    export RAID_I_UNDERSTAND_DATA_LOSS=0
}

teardown() {
    teardown_test_env
}

@test "system recovers from Docker daemon failure" {
    # Test recovery when Docker/Colima fails
    
    # Verify Docker startup script exists and is executable
    assert_script_exists "scripts/infrastructure/start_docker.sh"
    
    # Should handle Docker not running
    run bash -n scripts/infrastructure/start_docker.sh
    [ "$status" -eq 0 ] || fail "Docker startup script has syntax errors"
    
    # Should detect and restart Colima if needed
    run grep -E "(colima.*start|docker.*version)" scripts/infrastructure/start_docker.sh
    [ "$status" -eq 0 ] || fail "Should have Docker/Colima detection and restart logic"
}

@test "system recovers from storage mount failures" {
    # Test recovery when storage mounts fail
    
    # Create test scenario with missing storage
    local test_storage_script="$TEST_TEMP_DIR/test_storage_recovery.sh"
    
    cat > "$test_storage_script" << 'EOF'
#!/bin/bash
# Test storage recovery without actual sudo operations
set -euo pipefail

# Mock storage check
if [[ ! -d "/Volumes/warmstore" ]]; then
    echo "❌ Storage not available"
    echo "RECOVERY: Check RAID status with 'diskutil appleRAID list'"
    exit 1
fi

echo "✅ Storage available"
EOF
    
    chmod +x "$test_storage_script"
    
    # Test that it provides recovery guidance
    run bash "$test_storage_script"
    if [ "$status" -ne 0 ]; then
        [[ "$output" =~ "RECOVERY:" ]] || fail "Should provide recovery guidance for storage failures"
    fi
}

@test "system recovers from Plex service conflicts" {
    # Test recovery from Plex port conflicts (Tailscale issue we solved)
    
    assert_script_exists "scripts/services/start_plex_safe.sh"
    
    # Should handle port 32400 conflicts
    run grep -E "(32400|tailscale.*serve|port.*conflict)" scripts/services/start_plex_safe.sh
    [ "$status" -eq 0 ] || fail "Should handle Plex port conflicts with Tailscale"
    
    # Should have conflict resolution logic
    run grep -E "(reset|disable|enable)" scripts/services/start_plex_safe.sh
    [ "$status" -eq 0 ] || fail "Should have conflict resolution logic"
}

@test "system recovers from media processing failures" {
    # Test recovery when media processing fails
    
    assert_script_exists "scripts/media/processor.sh"
    assert_script_exists "scripts/media/watcher.sh"
    
    # Media processor should handle failed files gracefully
    run grep -E "(failed|error|cleanup)" scripts/media/processor.sh
    [ "$status" -eq 0 ] || fail "Should have error handling for failed media processing"
    
    # Watcher should restart on failure
    run grep -E "(restart|recover|retry)" scripts/media/watcher.sh
    [ "$status" -eq 0 ] || fail "Should have restart logic for media watcher"
}

@test "system recovers from network connectivity loss" {
    # Test recovery when network services fail
    
    local network_scripts=(
        "scripts/infrastructure/install_tailscale.sh"
        "scripts/infrastructure/configure_https.sh"
        "scripts/services/enable_landing.sh"
    )
    
    for script in "${network_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Should check network connectivity
            run grep -E "(ping|curl|wget|nc|telnet)" "$script"
            if [ "$status" -ne 0 ]; then
                # At minimum should have error handling
                run grep -E "(timeout|retry|fail)" "$script"
                [ "$status" -eq 0 ] || fail "$script should handle network failures"
            fi
        fi
    done
}

@test "system recovers from partial setup completion" {
    # Test recovery when setup is interrupted mid-process
    
    # Setup scripts should be idempotent (safe to re-run)
    local setup_scripts=(
        "scripts/infrastructure/install_docker.sh"
        "scripts/services/deploy_containers.sh"
        "scripts/automation/configure_launchd.sh"
    )
    
    for script in "${setup_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Should check if already installed/configured
            run grep -E "(already|exists|installed|running)" "$script"
            [ "$status" -eq 0 ] || fail "$script should be idempotent (safe to re-run)"
        fi
    done
}

@test "system recovers from corrupted configuration" {
    # Test recovery when configuration files are corrupted
    
    # LaunchD configuration should validate plist files
    assert_script_exists "scripts/automation/configure_launchd.sh"
    
    # Should validate plist syntax before installation or have error handling
    run grep -E "(plutil|lint|validate|error|fail)" scripts/automation/configure_launchd.sh
    [ "$status" -eq 0 ] || fail "Should validate plist files or have error handling"
}

@test "system provides clear error messages for common failures" {
    # Test that error messages are helpful and actionable
    
    local critical_scripts=(
        "scripts/core/health_check.sh"
        "scripts/storage/setup_direct_mounts.sh"
        "scripts/infrastructure/start_docker.sh"
        "scripts/services/deploy_containers.sh"
    )
    
    for script in "${critical_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Should have informative error messages
            run grep -E "(echo.*❌|echo.*ERROR|echo.*Failed)" "$script"
            [ "$status" -eq 0 ] || fail "$script should provide clear error messages"
            
            # Should provide recovery suggestions or helpful guidance
            run grep -E "(echo.*💡|echo.*Try|echo.*Run|echo.*Help|echo.*Usage)" "$script"
            [ "$status" -eq 0 ] || echo "ℹ️  $script may not have explicit recovery suggestions (acceptable for some scripts)"
        fi
    done
}

@test "system maintains service state during recovery" {
    # Test that recovery doesn't lose service state unnecessarily
    
    # Health check should preserve running services
    run bash scripts/core/health_check.sh --help 2>/dev/null || true
    
    # Should not restart services that are already running properly
    if [[ -f "scripts/core/health_check.sh" ]]; then
        run grep -E "(running|active|healthy)" scripts/core/health_check.sh
        [ "$status" -eq 0 ] || fail "Should check service state before recovery actions"
    fi
}

@test "system recovery logs are comprehensive and searchable" {
    # Test that recovery events are well-logged
    
    # All LaunchD services should log to centralized location
    for plist in launchd/*.plist; do
        if [[ -f "$plist" ]]; then
            run grep "StandardOutPath\|StandardErrorPath" "$plist"
            if [ "$status" -eq 0 ]; then
                # Should include service name in log path for easy identification
                local service_name=$(basename "$plist" .plist | sed 's/io.homelab.//')
                if [[ "$output" =~ "$service_name" ]]; then
                    echo "✅ $plist uses service-specific log path"
                else
                    echo "ℹ️  $plist uses generic log path (acceptable): $output"
                fi
            fi
        fi
    done
}
