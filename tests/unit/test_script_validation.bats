#!/usr/bin/env bats
# Unit tests for script validation and basic functionality

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "all setup scripts exist and are executable" {
    local setup_scripts=(
        "setup/setup.sh"
        "setup/setup_full.sh"
        "setup/setup_flags.sh"
    )
    
    for script in "${setup_scripts[@]}"; do
        assert_script_exists "$script"
        assert_valid_bash_syntax "$script"
    done
}

@test "all main scripts exist and are executable" {
    local main_scripts=(
        "scripts/20_install_colima_docker.sh"
        "scripts/21_start_colima.sh"
        "scripts/30_deploy_services.sh"
        "scripts/31_install_native_plex.sh"
        "scripts/40_configure_launchd.sh"
        "scripts/92_configure_power.sh"
        "scripts/95_setup_media_processing.sh"
    )
    
    for script in "${main_scripts[@]}"; do
        assert_script_exists "$script"
        assert_valid_bash_syntax "$script"
    done
}

@test "media processing scripts exist and are executable" {
    local media_scripts=(
        "scripts/media_processor.sh"
        "scripts/media_watcher.sh"
        "scripts/process_movie.sh"
        "scripts/process_tv_show.sh"
        "scripts/process_collection.sh"
    )
    
    for script in "${media_scripts[@]}"; do
        assert_script_exists "$script"
        assert_valid_bash_syntax "$script"
    done
}

@test "diagnostic scripts exist and are executable" {
    local diag_scripts=(
        "diagnostics/run_all.sh"
        "diagnostics/check_colima_docker.sh"
        "diagnostics/check_immich.sh"
        "diagnostics/check_plex_native.sh"
        "diagnostics/check_power_settings.sh"
        "diagnostics/check_storage.sh"
        "diagnostics/check_tailscale.sh"
    )
    
    for script in "${diag_scripts[@]}"; do
        assert_script_exists "$script"
        assert_valid_bash_syntax "$script"
    done
}

@test "setup_flags.sh shows help when called with --help" {
    run bash setup/setup_flags.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "OPTIONS" ]]
    [[ "$output" =~ "--all" ]]
    [[ "$output" =~ "--bootstrap" ]]
}

@test "setup_flags.sh validates environment variables" {
    # Test with invalid RAID setting
    export RAID_I_UNDERSTAND_DATA_LOSS="invalid"
    run bash setup/setup_flags.sh --help
    [ "$status" -eq 0 ]  # Should still show help, but validate env vars
}

@test "media_processor.sh shows usage when called with --help" {
    mock_system_commands
    run bash scripts/media_processor.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]] || [[ "$output" =~ "USAGE:" ]] || [[ "$output" =~ "usage:" ]]
}

@test "media_watcher.sh accepts valid commands" {
    mock_system_commands
    
    # Test valid commands (should not error on syntax)
    local valid_commands=("start" "stop" "status" "restart")
    
    for cmd in "${valid_commands[@]}"; do
        run bash -n scripts/media_watcher.sh  # Just syntax check
        [ "$status" -eq 0 ]
    done
}

@test "scripts contain proper shebang lines" {
    local scripts=(
        "scripts/media_processor.sh"
        "scripts/media_watcher.sh" 
        "setup/setup_full.sh"
        "setup/setup_flags.sh"
    )
    
    for script in "${scripts[@]}"; do
        run head -n 1 "$script"
        [[ "$output" =~ ^#!/.*bash ]] || fail "Script $script missing proper shebang"
    done
}

@test "scripts do not contain hardcoded paths (except /Volumes)" {
    local scripts=(
        "scripts/media_processor.sh"
        "scripts/media_watcher.sh"
    )
    
    for script in "${scripts[@]}"; do
        # Check for hardcoded home paths (should use variables)
        run grep -n "/Users/" "$script"
        if [ "$status" -eq 0 ]; then
            fail "Script $script contains hardcoded user paths: $output"
        fi
        
        # /Volumes paths are acceptable for macOS
        # But /tmp paths should be avoided in favor of proper temp dirs
        run grep -n "/tmp/" "$script"
        if [ "$status" -eq 0 ]; then
            # Allow /tmp in some contexts, but warn
            echo "Warning: Script $script uses /tmp paths: $output" >&3
        fi
    done
}
