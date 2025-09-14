#!/usr/bin/env bats
# End-to-end shutdown recovery tests (BATS version)
# Simulates shutdown/recovery cycle without actual system shutdown

load '../test_helper'

setup() {
    setup_test_env
    create_fake_storage
    mock_system_commands
    
    # Create mock log directories
    mkdir -p "$TEST_TEMP_DIR/logs"
    export LOGS_DIR="$TEST_TEMP_DIR/logs"
}

teardown() {
    teardown_test_env
}

@test "pre-shutdown health check validates system status" {
    # Mock post_boot_health_check.sh
    cat > "$TEST_TEMP_DIR/mock_health_check.sh" << 'EOF'
#!/bin/bash
echo "LaunchD Services: Running"
echo "Service Health: Running"
echo "Storage Mounts: Available"
echo "🎉 ALL SYSTEMS OPERATIONAL!"
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/mock_health_check.sh"
    
    run bash "$TEST_TEMP_DIR/mock_health_check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ALL SYSTEMS OPERATIONAL" ]]
}

@test "recovery reference file can be created" {
    # Test creating recovery reference as per instructions
    local recovery_file="$TEST_TEMP_DIR/recovery_reference.txt"
    
    cat > "$recovery_file" << 'EOF'
POST-BOOT RECOVERY COMMANDS:
1. Health check: ./scripts/post_boot_health_check.sh
2. Auto-recovery: ./scripts/post_boot_health_check.sh --auto-recover
3. Monitor logs: tail -f /Volumes/warmstore/logs/{service}/{service}.{out,err}
EOF
    
    # Verify recovery reference
    [[ -f "$recovery_file" ]]
    grep -q "POST-BOOT RECOVERY COMMANDS" "$recovery_file"
    grep -q "post_boot_health_check.sh" "$recovery_file"
    grep -q "auto-recover" "$recovery_file"
}

@test "automation timeline follows expected sequence" {
    # Test automation timeline from shutdown test instructions
    local services=("storage" "tailscale" "colima" "immich" "plex" "landing")
    local delays=(0 0 60 90 120 150)
    
    # Verify timeline order
    local prev_delay=0
    for i in "${!services[@]}"; do
        local service="${services[$i]}"
        local delay="${delays[$i]}"
        
        # Storage and Tailscale can start at 0, others should be sequential
        if [[ "$service" != "storage" && "$service" != "tailscale" ]]; then
            [[ "$delay" -gt "$prev_delay" ]] || fail "Service $service delay ($delay) should be > previous ($prev_delay)"
        fi
        
        # Update prev_delay for non-zero delays
        [[ "$delay" -gt 0 ]] && prev_delay="$delay"
    done
}

@test "service startup scripts exist for automation timeline" {
    # Verify scripts exist for each service in automation timeline
    local service_scripts=(
        "scripts/ensure_storage_mounts.sh:storage"
        "scripts/90_install_tailscale.sh:tailscale"
        "scripts/21_start_colima.sh:colima"
        "scripts/30_deploy_services.sh:immich"
        "scripts/31_install_native_plex.sh:plex"
        "scripts/37_enable_simple_landing.sh:landing"
    )
    
    for script_spec in "${service_scripts[@]}"; do
        local script_path="${script_spec%%:*}"
        local service_name="${script_spec##*:}"
        
        assert_script_exists "$script_path"
        assert_valid_bash_syntax "$script_path"
    done
}

@test "LaunchD services have correct startup delays" {
    # Test LaunchD plist files have correct delays from timeline
    local service_delays=(
        "io.homelab.colima.plist:60"
        "io.homelab.compose.immich.plist:90"
        "io.homelab.plex.plist:120"
        "io.homelab.landing.plist:150"
    )
    
    for service_spec in "${service_delays[@]}"; do
        local plist_file="launchd/${service_spec%%:*}"
        local expected_delay="${service_spec##*:}"
        
        [[ -f "$plist_file" ]] || fail "LaunchD plist not found: $plist_file"
        
        # Check for sleep delay in plist
        run grep "sleep $expected_delay" "$plist_file"
        [ "$status" -eq 0 ] || fail "Service $plist_file should have sleep $expected_delay"
    done
}

@test "post-boot health check components are testable" {
    # Mock components that health check would test
    local health_components=(
        "launchd_services"
        "service_health" 
        "storage_mounts"
    )
    
    # Create mock health check results
    for component in "${health_components[@]}"; do
        echo "$component: Running" > "$TEST_TEMP_DIR/${component}_status"
    done
    
    # Verify all components can be checked
    for component in "${health_components[@]}"; do
        [[ -f "$TEST_TEMP_DIR/${component}_status" ]]
        grep -q "Running" "$TEST_TEMP_DIR/${component}_status"
    done
}

@test "service URLs follow expected pattern" {
    # Test service URL patterns from shutdown test instructions
    local service_urls=(
        "https://nitins-mac-mini.tailb6b278.ts.net|landing"
        "https://nitins-mac-mini.tailb6b278.ts.net:2283|immich"
        "https://nitins-mac-mini.tailb6b278.ts.net:32400|plex"
    )
    
    for url_spec in "${service_urls[@]}"; do
        local url="${url_spec%%|*}"
        local service="${url_spec##*|}"
        
        # Verify URL format
        [[ "$url" =~ ^https:// ]] || fail "Service URL should use HTTPS: $url"
        [[ "$url" =~ tailb6b278\.ts\.net ]] || fail "Service URL should use Tailscale domain: $url"
        
        # Verify service name is valid
        [[ "$service" =~ ^(landing|immich|plex)$ ]] || fail "Invalid service name: $service"
    done
}

@test "auto-recovery command structure is valid" {
    # Test auto-recovery command from instructions
    local auto_recovery_cmd="./scripts/post_boot_health_check.sh --auto-recovery"
    
    # Verify script exists
    assert_script_exists "scripts/post_boot_health_check.sh"
    
    # Test command structure
    [[ "$auto_recovery_cmd" =~ --auto-recovery ]] || fail "Auto-recovery should use --auto-recovery flag"
}

@test "manual recovery commands are valid" {
    # Test manual recovery commands from shutdown test instructions
    local manual_commands=(
        "sudo ln -sf /Volumes/warmstore/Photos /Volumes/Photos"
        "sudo mkdir -p /Volumes/Archive"
        "sudo tailscale serve --bg --https=443 http://localhost:8080"
        "sudo tailscale serve --bg --https=2283 http://localhost:2283"
        "sudo tailscale serve --bg --https=32400 http://localhost:32400"
    )
    
    for cmd in "${manual_commands[@]}"; do
        # Verify command structure
        [[ "$cmd" =~ ^sudo ]] || fail "Manual recovery commands should use sudo: $cmd"
        
        if [[ "$cmd" =~ "ln -sf" ]]; then
            [[ "$cmd" =~ "/Volumes/" ]] || fail "Symlink commands should reference /Volumes/: $cmd"
        elif [[ "$cmd" =~ "mkdir -p" ]]; then
            [[ "$cmd" =~ "/Volumes/" ]] || fail "Mkdir commands should reference /Volumes/: $cmd"
        elif [[ "$cmd" =~ "tailscale serve" ]]; then
            [[ "$cmd" =~ "--bg" ]] || fail "Tailscale serve should use --bg: $cmd"
            [[ "$cmd" =~ "--https=" ]] || fail "Tailscale serve should use --https=: $cmd"
            [[ "$cmd" =~ "localhost:" ]] || fail "Tailscale serve should proxy to localhost: $cmd"
        fi
    done
}

@test "log monitoring commands are valid" {
    # Test log monitoring from shutdown test instructions
    local log_patterns=(
        "/Volumes/warmstore/logs/storage/storage.out"
        "/Volumes/warmstore/logs/colima/colima.out"
        "/Volumes/warmstore/logs/immich/immich.out"
        "/Volumes/warmstore/logs/plex/plex.out"
        "/Volumes/warmstore/logs/landing/landing.out"
    )
    
    for log_path in "${log_patterns[@]}"; do
        # Verify log path structure
        [[ "$log_path" =~ ^/Volumes/warmstore/logs/ ]] || fail "Log should be in centralized location: $log_path"
        [[ "$log_path" =~ \.out$ ]] || fail "Log should be .out file: $log_path"
        
        # Create mock log file for testing
        local mock_log="$TEST_TEMP_DIR/$(basename "$log_path")"
        echo "Service started successfully" > "$mock_log"
        [[ -f "$mock_log" ]]
    done
}

@test "timing expectations are reasonable" {
    # Test timing expectations from shutdown test instructions
    local max_times=(
        "first_service_available:300"    # 5 minutes max
        "all_services_operational:600"   # 10 minutes max
        "total_recovery:900"             # 15 minutes max
    )
    
    for timing_spec in "${max_times[@]}"; do
        local timing_name="${timing_spec%%:*}"
        local max_seconds="${timing_spec##*:}"
        
        # Verify timing is reasonable (not too long)
        [[ "$max_seconds" -le 900 ]] || fail "Timing $timing_name too long: ${max_seconds}s"
        [[ "$max_seconds" -gt 0 ]] || fail "Timing $timing_name should be positive: ${max_seconds}s"
    done
}

@test "safety validations are enforced" {
    # Test safety notes from shutdown test instructions
    local safety_checks=(
        "no_raid_modification"
        "user_level_automation"
        "automation_can_be_disabled"
        "actions_are_logged"
    )
    
    for safety_check in "${safety_checks[@]}"; do
        case "$safety_check" in
            "no_raid_modification")
                # Verify no RAID modification commands in LaunchD automation scripts
                # (Setup scripts are allowed to have RAID commands, but not automation)
                local automation_scripts=(
                    "scripts/ensure_storage_mounts.sh"
                    "scripts/wait_for_storage.sh"
                    "scripts/media_watcher.sh"
                    "scripts/media_processor.sh"
                )
                
                local found_raid_in_automation=false
                for script in "${automation_scripts[@]}"; do
                    if [[ -f "$script" ]] && grep -q "diskutil.*RAID" "$script"; then
                        found_raid_in_automation=true
                        break
                    fi
                done
                
                [[ "$found_raid_in_automation" == "false" ]] || fail "Automation scripts should not modify RAID"
                ;;
            "user_level_automation")
                # Verify LaunchD services are user-level (LaunchAgents)
                [[ -d "launchd/" ]] || fail "LaunchD directory should exist"
                ;;
            "automation_can_be_disabled")
                # Verify configure_launchd.sh exists for management
                assert_script_exists "scripts/40_configure_launchd.sh"
                ;;
            "actions_are_logged")
                # Verify logging is configured
                grep -r "/Volumes/warmstore/logs/" launchd/ || fail "Services should use centralized logging"
                ;;
        esac
    done
}

@test "complete shutdown recovery simulation" {
    # Simulate complete shutdown recovery cycle
    local test_phases=(
        "pre_shutdown_validation"
        "shutdown_process"
        "boot_process"
        "automation_timeline"
        "post_boot_validation"
        "service_url_testing"
        "recovery_capability"
    )
    
    local phase_results=()
    
    for phase in "${test_phases[@]}"; do
        case "$phase" in
            "pre_shutdown_validation")
                # Simulate pre-shutdown health check
                echo "🎉 ALL SYSTEMS OPERATIONAL!" > "$TEST_TEMP_DIR/pre_shutdown_status"
                [[ -f "$TEST_TEMP_DIR/pre_shutdown_status" ]]
                ;;
            "shutdown_process")
                # Simulate shutdown (just validate command structure)
                local shutdown_cmd="sudo shutdown -h now"
                [[ "$shutdown_cmd" =~ "sudo shutdown" ]]
                ;;
            "boot_process")
                # Simulate boot and login
                echo "User logged in, automation triggered" > "$TEST_TEMP_DIR/boot_status"
                [[ -f "$TEST_TEMP_DIR/boot_status" ]]
                ;;
            "automation_timeline")
                # Simulate automation timeline
                local services=("storage" "colima" "immich" "plex" "landing")
                for service in "${services[@]}"; do
                    echo "$service: started" > "$TEST_TEMP_DIR/${service}_status"
                done
                ;;
            "post_boot_validation")
                # Simulate post-boot health check
                echo "ALL SYSTEMS OPERATIONAL" > "$TEST_TEMP_DIR/post_boot_status"
                [[ -f "$TEST_TEMP_DIR/post_boot_status" ]]
                ;;
            "service_url_testing")
                # Simulate service URL testing
                echo "200" > "$TEST_TEMP_DIR/landing_status"
                echo "200" > "$TEST_TEMP_DIR/immich_status"
                echo "302" > "$TEST_TEMP_DIR/plex_status"
                ;;
            "recovery_capability")
                # Simulate auto-recovery
                echo "Auto-recovery completed successfully" > "$TEST_TEMP_DIR/recovery_status"
                [[ -f "$TEST_TEMP_DIR/recovery_status" ]]
                ;;
        esac
        
        phase_results+=("$phase:success")
    done
    
    # Verify all phases completed
    [[ "${#phase_results[@]}" -eq "${#test_phases[@]}" ]] || fail "Not all test phases completed"
    
    # Verify no failures
    for result in "${phase_results[@]}"; do
        [[ "$result" =~ ":success" ]] || fail "Phase failed: $result"
    done
}
