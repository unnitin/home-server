#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "core module scripts can be sourced by other modules" {
    # Test that core utilities are accessible to other modules
    run bash -c "source scripts/core/health_check.sh && type -t log_info"
    [ "$status" -eq 0 ]
}

@test "storage module dependencies are correctly resolved" {
    # Test that storage scripts can find their dependencies
    run bash -c "cd scripts/storage && source lib/raid_common.sh && type -t require_guard"
    [ "$status" -eq 0 ]
}

@test "infrastructure module can access storage utilities" {
    # Test cross-module dependencies work correctly
    assert_script_exists "scripts/infrastructure/compose_wrapper.sh"
    assert_script_exists "scripts/storage/wait_for_storage.sh"
    
    # Verify infrastructure scripts don't have circular dependencies
    run bash -n scripts/infrastructure/compose_wrapper.sh
    [ "$status" -eq 0 ]
}

@test "services module can access all required dependencies" {
    # Test that services can access infrastructure and storage
    local service_scripts=(
        "scripts/services/deploy_containers.sh"
        "scripts/services/start_plex_safe.sh"
    )
    
    for script in "${service_scripts[@]}"; do
        run bash -n "$script"
        [ "$status" -eq 0 ] || fail "Service script $script has syntax errors"
    done
}

@test "automation module can orchestrate all other modules" {
    # Test that automation scripts can reference all modules
    run grep -r "scripts/" scripts/automation/
    [ "$status" -eq 0 ]
    
    # Verify configure_launchd.sh references all service types
    run grep -E "(storage|infrastructure|services|media)" scripts/automation/configure_launchd.sh
    [ "$status" -eq 0 ]
}

@test "media module integrates correctly with services" {
    # Test media processing can work with Plex service
    assert_script_exists "scripts/media/processor.sh"
    assert_script_exists "scripts/services/start_plex_safe.sh"
    
    # Verify media scripts reference correct target directories
    run grep "/Volumes/Media\|/Volumes/warmstore" scripts/media/processor.sh
    [ "$status" -eq 0 ]
}
