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

@test "setup_full.sh references all required modular scripts" {
    # Test that setup_full.sh uses correct new script paths
    local expected_scripts=(
        "scripts/infrastructure/install_docker.sh"
        "scripts/infrastructure/start_docker.sh"
        "scripts/storage/preclean_disks.sh"
        "scripts/storage/create_ssd_raid.sh"
        "scripts/storage/ensure_mounts.sh"
        "scripts/services/deploy_containers.sh"
        "scripts/services/install_plex.sh"
        "scripts/automation/configure_launchd.sh"
        "scripts/infrastructure/install_tailscale.sh"
        "scripts/infrastructure/configure_https.sh"
        "scripts/infrastructure/configure_power.sh"
        "scripts/services/enable_landing.sh"
    )
    
    for script in "${expected_scripts[@]}"; do
        run grep "$script" setup/setup_full.sh
        [ "$status" -eq 0 ] || fail "setup_full.sh should reference $script"
    done
}

@test "setup_flags.sh supports all modular script operations" {
    # Test that setup_flags.sh has correct flags for all modules
    run bash setup/setup_flags.sh --help
    [ "$status" -eq 0 ]
    
    # Verify key flags exist
    [[ "$output" =~ "--bootstrap" ]] || fail "Missing bootstrap flag"
    [[ "$output" =~ "--colima" ]] || fail "Missing colima flag"
    [[ "$output" =~ "--storage-mounts" ]] || fail "Missing storage-mounts flag"
    [[ "$output" =~ "--immich" ]] || fail "Missing immich flag"
    [[ "$output" =~ "--plex" ]] || fail "Missing plex flag"
    [[ "$output" =~ "--launchd" ]] || fail "Missing launchd flag"
}

@test "dry-run setup executes without errors" {
    # Test that setup can run in dry-run mode without breaking
    run bash setup/setup_flags.sh --bootstrap --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" =~ "DRY:" ]] || fail "Dry run should show DRY: prefix"
}

@test "setup workflow follows correct dependency order" {
    # Test that setup scripts are called in correct dependency order
    local setup_content
    setup_content=$(cat setup/setup_full.sh)
    
    # Infrastructure should come before services
    local infra_line=$(echo "$setup_content" | grep -n "infrastructure/install_docker.sh" | cut -d: -f1)
    local service_line=$(echo "$setup_content" | grep -n "services/deploy_containers.sh" | cut -d: -f1)
    
    [ "$infra_line" -lt "$service_line" ] || fail "Infrastructure should be set up before services"
}

@test "setup handles missing environment variables gracefully" {
    # Test setup behavior with missing required variables
    unset SSD_DISKS NVME_DISKS COLD_DISKS
    
    run bash setup/setup_flags.sh --help
    [ "$status" -eq 0 ]
    
    # Should still show help even without environment variables
    [[ "$output" =~ "ENVIRONMENT" ]] || fail "Should show environment variable section"
}
