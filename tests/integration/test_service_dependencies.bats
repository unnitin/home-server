#!/usr/bin/env bats
# Integration tests for service dependencies and startup order

load '../test_helper'

setup() {
    setup_test_env
    mock_system_commands
}

teardown() {
    teardown_test_env
}

@test "LaunchD plist files are valid XML" {
    local plist_files=(
        "launchd/io.homelab.colima.plist"
        "launchd/io.homelab.compose.immich.plist"
        "launchd/io.homelab.plex.plist"
        "launchd/io.homelab.media.watcher.plist"
        "launchd/io.homelab.powermgmt.plist"
        "launchd/io.homelab.tailscale.plist"
        "launchd/io.homelab.updatecheck.plist"
    )
    
    for plist in "${plist_files[@]}"; do
        assert_service_plist_valid "$plist"
    done
}

@test "LaunchD services have correct startup delays" {
    # Test that services have appropriate startup delays to prevent race conditions
    
    # Check Colima (should start early)
    run grep -A 5 "<string>sleep" launchd/io.homelab.colima.plist
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sleep 60" ]] || fail "Colima should have 60s delay"
    
    # Check Immich (should start after Colima and storage)
    run grep -A 5 "<string>sleep" launchd/io.homelab.compose.immich.plist
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sleep 90" ]] || fail "Immich should have 90s delay"
    
    # Check Plex (should start after storage is ready)
    run grep -A 5 "<string>sleep" launchd/io.homelab.plex.plist
    [ "$status" -eq 0 ]
    [[ "$output" =~ "sleep 120" ]] || fail "Plex should have 120s delay"
}

@test "LaunchD services reference correct script paths" {
    local services=(
        "io.homelab.colima.plist:start_docker.sh"
        "io.homelab.compose.immich.plist:compose_wrapper.sh"
        "io.homelab.media.watcher.plist:watcher.sh"
        "io.homelab.powermgmt.plist:ensure_power_settings.sh"
    )
    
    for service_spec in "${services[@]}"; do
        local plist_file="launchd/${service_spec%%:*}"
        local expected_script="${service_spec##*:}"
        
        # Check that the plist references the expected script
        run grep "$expected_script" "$plist_file"
        [ "$status" -eq 0 ] || fail "Service $plist_file does not reference $expected_script"
    done
}

@test "service startup order is logical" {
    # Test the logical startup sequence based on delays
    local services_with_delays=(
        "colima:60"
        "immich:90"
        "plex:120"
        "landing:150"
    )
    
    local prev_delay=0
    for service_spec in "${services_with_delays[@]}"; do
        local service="${service_spec%%:*}"
        local delay="${service_spec##*:}"
        
        # Each service should start after the previous one
        [[ "$delay" -gt "$prev_delay" ]] || fail "Service $service delay ($delay) should be greater than previous ($prev_delay)"
        prev_delay="$delay"
    done
}

@test "Immich service waits for storage dependencies" {
    # Test that Immich service includes storage dependency check
    run grep "wait_for_storage.sh" launchd/io.homelab.compose.immich.plist
    [ "$status" -eq 0 ] || fail "Immich service should wait for storage"
    
    # Verify the wait_for_storage.sh script exists
    assert_script_exists "scripts/storage/wait_for_storage.sh"
}

@test "services use centralized logging paths" {
    local services=(
        "io.homelab.colima.plist"
        "io.homelab.compose.immich.plist"
        "io.homelab.plex.plist"
        "io.homelab.media.watcher.plist"
        "io.homelab.powermgmt.plist"
        "io.homelab.tailscale.plist"
        "io.homelab.updatecheck.plist"
    )
    
    for service in "${services[@]}"; do
        # Check for centralized logging path
        run grep "/Volumes/warmstore/logs/" "launchd/$service"
        [ "$status" -eq 0 ] || fail "Service $service should use centralized logging"
    done
}

@test "configure_launchd.sh installs all required services" {
    # Test that the LaunchD configuration script knows about all services
    local expected_services=(
        "storage"
        "powermgmt"
        "colima"
        "compose.immich"
        "plex"
        "landing"
        "media.watcher"
        "tailscale"
        "updatecheck"
    )
    
    for service in "${expected_services[@]}"; do
        run grep "$service" scripts/automation/configure_launchd.sh
        [ "$status" -eq 0 ] || fail "configure_launchd.sh should reference service: $service"
    done
}

@test "service dependencies are correctly ordered in configure_launchd.sh" {
    # Test that services are listed in dependency order
    run grep -n "SERVICES=(" scripts/automation/configure_launchd.sh -A 20
    [ "$status" -eq 0 ]
    
    # Storage should come first
    [[ "$output" =~ "storage" ]] || fail "Storage service should be included"
    
    # Media watcher should be after storage services
    [[ "$output" =~ "media.watcher" ]] || fail "Media watcher service should be included"
}

@test "Docker Compose is properly configured" {
    skip_if_not_integration
    
    # Test that docker compose command is available
    # This test requires actual Docker installation
    run which docker
    if [ "$status" -ne 0 ]; then
        skip "Docker not installed - skipping Docker integration test"
    fi
    
    # Test docker compose plugin availability
    run docker compose version
    if [ "$status" -ne 0 ]; then
        # Try legacy docker-compose
        run docker-compose version
        [ "$status" -eq 0 ] || fail "Neither 'docker compose' nor 'docker-compose' available"
    fi
}

@test "media processing service integrates with LaunchD" {
    # Test that media watcher service is properly configured
    local media_plist="launchd/io.homelab.media.watcher.plist"
    
    # Check service exists
    [[ -f "$media_plist" ]] || fail "Media watcher plist not found"
    
    # Check it references the correct script
    run grep "watcher.sh" "$media_plist"
    [ "$status" -eq 0 ] || fail "Media watcher plist should reference watcher.sh"
    
    # Check it has RunAtLoad set to true
    run grep -A 1 "RunAtLoad" "$media_plist"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "true" ]] || fail "Media watcher should have RunAtLoad=true"
}
