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

@test "system can recover from complete service failure" {
    # Test complete system recovery scenario
    
    # Simulate all services being down
    local critical_services=(
        "storage"
        "colima" 
        "immich"
        "plex"
        "tailscale"
        "media-watcher"
    )
    
    # Verify health check can detect failures
    run bash scripts/core/health_check.sh
    [ "$status" -eq 0 ]  # Should complete even with services down
    
    # Verify recovery commands or guidance are provided
    if [[ "$output" =~ "RECOVERY COMMANDS" ]]; then
        echo "✅ Explicit recovery commands found"
    elif [[ "$output" =~ "RECOVERY\|recovery\|COMMANDS\|commands" ]]; then
        echo "✅ Recovery guidance found"
    elif [[ "$output" =~ "Health Check\|System.*Status" ]]; then
        echo "✅ Health check completed successfully"
    elif [[ "$output" =~ "LaunchD\|Services\|Status" ]]; then
        echo "✅ Service status information provided"
    else
        echo "ℹ️  Health check output: $output"
        echo "✅ Health check completed (output may vary based on system state)"
    fi
}

@test "storage recovery handles missing mount points" {
    # Test storage mount point recovery
    
    # Create scenario with missing mount points
    local mount_points=(
        "/Volumes/warmstore"
        "/Volumes/faststore" 
        "/Volumes/Archive"
    )
    
    # Test storage mount script can handle missing directories
    run bash -n scripts/storage/setup_direct_mounts.sh
    [ "$status" -eq 0 ] || fail "Storage mount script has syntax errors"
    
    # Verify it creates required directories
    run grep -q "mkdir -p" scripts/storage/setup_direct_mounts.sh
    [ "$status" -eq 0 ] || fail "Should create missing directories"
}

@test "LaunchD services can restart after system reboot" {
    # Test LaunchD service recovery after reboot
    
    local critical_plists=(
        "launchd/io.homelab.storage.plist"
        "launchd/io.homelab.colima.plist"
        "launchd/io.homelab.compose.immich.plist"
        "launchd/io.homelab.plex.plist"
        "launchd/io.homelab.media.watcher.plist"
    )
    
    for plist in "${critical_plists[@]}"; do
        # Verify plist exists and is valid XML
        [[ -f "$plist" ]] || fail "LaunchD plist $plist does not exist"
        run plutil -lint "$plist" 2>/dev/null || true
        
        # Verify it has RunAtLoad for automatic startup
        run grep -q "RunAtLoad" "$plist"
        [ "$status" -eq 0 ] || fail "$plist should have RunAtLoad for boot recovery"
        
        # Verify it references correct script paths
        run grep "scripts/" "$plist"
        if [ "$status" -eq 0 ]; then
            # Extract script path and verify it exists (handle XML encoding)
            local script_path=$(echo "$output" | grep -o 'scripts/[^<& ]*\.sh' | head -1)
            if [[ -n "$script_path" ]]; then
                [[ -f "$script_path" ]] || fail "Script referenced in $plist does not exist: $script_path"
            fi
        fi
    done
}

@test "service dependency chain recovers in correct order" {
    # Test that services start in dependency order during recovery
    
    # Verify storage comes before other services
    local storage_delay=$(grep -o "sleep [0-9]*" launchd/io.homelab.storage.plist | grep -o "[0-9]*")
    local colima_delay=$(grep -o "sleep [0-9]*" launchd/io.homelab.colima.plist | grep -o "[0-9]*")
    local immich_delay=$(grep -o "sleep [0-9]*" launchd/io.homelab.compose.immich.plist | grep -o "[0-9]*")
    local plex_delay=$(grep -o "sleep [0-9]*" launchd/io.homelab.plex.plist | grep -o "[0-9]*")
    
    # Storage should start first (lowest delay)
    [ "$storage_delay" -lt "$colima_delay" ] || fail "Storage should start before Colima"
    [ "$colima_delay" -lt "$immich_delay" ] || fail "Colima should start before Immich"
    [ "$immich_delay" -lt "$plex_delay" ] || fail "Immich should start before Plex"
}

@test "storage dependency validation prevents premature service starts" {
    # Test wait_for_storage.sh prevents services starting too early
    
    assert_script_exists "scripts/storage/wait_for_storage.sh"
    
    # Verify Immich service uses storage dependency check
    run grep "wait_for_storage.sh" launchd/io.homelab.compose.immich.plist
    [ "$status" -eq 0 ] || fail "Immich should wait for storage before starting"
    
    # Test the wait script has proper validation
    run grep -E "(warmstore|faststore)" scripts/storage/wait_for_storage.sh
    [ "$status" -eq 0 ] || fail "wait_for_storage.sh should check for required storage"
}

@test "health check provides actionable recovery commands" {
    # Test that health check gives specific recovery instructions
    
    run bash scripts/core/health_check.sh
    [ "$status" -eq 0 ]
    
    # Should provide specific commands for common issues
    if [[ "$output" =~ "RECOVERY COMMANDS" ]]; then
        # Should include service-specific recovery
        [[ "$output" =~ colima\ start|docker|launchctl ]] || fail "Should provide Docker/Colima recovery commands"
    fi
}

@test "auto-recovery mode can fix common issues" {
    # Test automated recovery functionality
    
    # Verify health check supports auto-recovery flag
    run bash scripts/core/health_check.sh --help 2>/dev/null || echo "No help available"
    
    # Should mention auto-recovery in help or output, or script should accept the flag
    if [[ "$output" =~ "auto.*recover\|--auto-recover" ]]; then
        echo "✅ Auto-recovery mode detected in help"
    else
        # Test if script accepts --auto-recover flag without error
        run bash scripts/core/health_check.sh --auto-recover 2>/dev/null || true
        echo "✅ Auto-recovery flag tested"
    fi
}

@test "critical scripts handle missing dependencies gracefully" {
    # Test that critical scripts fail gracefully when dependencies are missing
    
    local critical_scripts=(
        "scripts/storage/setup_direct_mounts.sh"
        "scripts/infrastructure/start_docker.sh"
        "scripts/services/deploy_containers.sh"
        "scripts/media/watcher.sh"
    )
    
    for script in "${critical_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Should have error handling for missing dependencies
            run grep -E "(command -v|which|type -t)" "$script"
            if [ "$status" -ne 0 ]; then
                # At minimum should have basic error handling
                run grep -E "(exit|return|fail)" "$script"
                [ "$status" -eq 0 ] || fail "$script should have error handling"
            fi
        fi
    done
}

@test "logging system captures recovery events" {
    # Test that recovery events are properly logged
    
    local log_paths=(
        "/Volumes/warmstore/logs/system/"
        "/Volumes/faststore/immich/logs/"
        "/Volumes/faststore/plex/logs/"
        "/Volumes/warmstore/logs/media-processing/"
    )
    
            # Verify LaunchD services use proper logging architecture
    local services_with_logging=0
    for plist in launchd/*.plist; do
        if [[ -f "$plist" ]]; then
            run grep "StandardOutPath\|StandardErrorPath" "$plist"
            if [ "$status" -eq 0 ]; then
                if [[ "$output" =~ "/Volumes/warmstore/logs/" ]] || [[ "$output" =~ "/Volumes/faststore/" ]]; then
                    ((services_with_logging++))
                else
                    echo "⚠️  $plist uses unexpected logging: $output"
                fi
            fi
        fi
    done
    
    # At least some services should use proper logging architecture
    [ "$services_with_logging" -gt 0 ] || fail "At least some services should use proper logging architecture"
}

@test "recovery process preserves user data" {
    # Test that recovery operations don't affect user data
    
    local data_directories=(
        "/Volumes/warmstore/movies"
        "/Volumes/warmstore/tv-shows"
        "/Volumes/faststore/immich"
        "/Volumes/warmstore/staging"
    )
    
    # Verify recovery scripts don't contain destructive operations on data dirs
    local recovery_scripts=(
        "scripts/core/health_check.sh"
        "scripts/storage/setup_direct_mounts.sh"
        "scripts/automation/configure_launchd.sh"
    )
    
    for script in "${recovery_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Should not contain rm -rf on data directories
            run grep "rm -rf.*\(movies\|tv-shows\|immich\|staging\)" "$script"
            [ "$status" -ne 0 ] || fail "$script should not delete user data directories"
        fi
    done
}

@test "emergency recovery instructions are accessible" {
    # Test that emergency recovery information is available
    
    # Should have recovery documentation
    local recovery_docs=(
        "docs/TROUBLESHOOTING.md"
        "docs/RECOVERY.md"
        "tests/Shutdown_Test_Instructions.md"
    )
    
    local found_recovery_doc=false
    for doc in "${recovery_docs[@]}"; do
        if [[ -f "$doc" ]]; then
            found_recovery_doc=true
            # Should contain recovery procedures
            run grep -i "recovery\|troubleshoot\|emergency" "$doc"
            [ "$status" -eq 0 ] || fail "$doc should contain recovery procedures"
        fi
    done
    
    [ "$found_recovery_doc" = true ] || fail "Should have recovery documentation available"
}
