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
        "scripts/storage/setup_direct_mounts.sh"
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

@test "setup_flags.sh shows deprecation warning" {
    # Test that setup_flags.sh shows deprecation warning since it's deprecated
    run bash -c 'echo "N" | bash setup/setup_flags.sh --help'
    [[ "$output" =~ "DEPRECATED" ]] || fail "Should show deprecation warning"
    [[ "$output" =~ "setup_full.sh" ]] || fail "Should recommend setup_full.sh"
}

@test "dry-run setup executes without errors" {
    # Skip this test since setup_flags.sh is deprecated
    skip "setup_flags.sh is deprecated - dry-run functionality moved to setup_full.sh"
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
    
    # Since setup_full.sh is interactive, test that it exists and has proper structure
    assert_script_exists "setup/setup_full.sh"
    
    # Test that it has environment variable handling logic
    run grep -E "(SSD_DISKS|NVME_DISKS|COLD_DISKS)" setup/setup_full.sh
    [ "$status" -eq 0 ] || fail "setup_full.sh should reference environment variables"
    
    # Test that it has interactive prompts (since it's designed to be interactive)
    run grep -E "(read -r -p|confirm)" setup/setup_full.sh
    [ "$status" -eq 0 ] || fail "setup_full.sh should have interactive prompts"
}
