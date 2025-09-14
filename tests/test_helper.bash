#!/usr/bin/env bash
# Test helper functions for BATS tests

# Set up test environment
setup_test_env() {
    export TEST_MODE=1
    export RAID_I_UNDERSTAND_DATA_LOSS=0
    export TEST_TEMP_DIR="${BATS_TMPDIR}/homeserver_test_$$"
    mkdir -p "$TEST_TEMP_DIR"
}

# Clean up test environment
teardown_test_env() {
    [[ -n "$TEST_TEMP_DIR" && -d "$TEST_TEMP_DIR" ]] && rm -rf "$TEST_TEMP_DIR"
}

# Mock external commands for safe testing
mock_command() {
    local cmd="$1"
    local mock_output="$2"
    local mock_exit_code="${3:-0}"
    
    # Create mock script in test temp dir
    cat > "$TEST_TEMP_DIR/mock_$cmd" << EOF
#!/bin/bash
echo "$mock_output"
exit $mock_exit_code
EOF
    chmod +x "$TEST_TEMP_DIR/mock_$cmd"
    
    # Add to PATH
    export PATH="$TEST_TEMP_DIR:$PATH"
    
    # Create alias
    alias "$cmd"="$TEST_TEMP_DIR/mock_$cmd"
}

# Check if script exists and is executable
assert_script_exists() {
    local script_path="$1"
    [[ -f "$script_path" ]] || fail "Script not found: $script_path"
    [[ -x "$script_path" ]] || fail "Script not executable: $script_path"
}

# Check if script has valid bash syntax
assert_valid_bash_syntax() {
    local script_path="$1"
    bash -n "$script_path" || fail "Invalid bash syntax in: $script_path"
}

# Mock sudo for safe testing
mock_sudo() {
    mock_command "sudo" ""
}

# Mock system commands that we don't want to actually run
mock_system_commands() {
    mock_command "launchctl" "com.example.test"
    mock_command "diskutil" "disk1"
    mock_command "pmset" "System-wide power settings"
    mock_command "brew" "Already installed"
    mock_command "docker" "Docker version 20.10.0"
    mock_sudo
}

# Create fake storage structure for testing
create_fake_storage() {
    mkdir -p "$TEST_TEMP_DIR/Volumes/warmstore"
    mkdir -p "$TEST_TEMP_DIR/Volumes/coldstore"
    mkdir -p "$TEST_TEMP_DIR/Volumes/Media"
    
    # Create fake mount points
    export WARMSTORE="$TEST_TEMP_DIR/Volumes/warmstore"
    export COLDSTORE="$TEST_TEMP_DIR/Volumes/coldstore"
}

# Assert that a log file contains expected content
assert_log_contains() {
    local log_file="$1"
    local expected_content="$2"
    
    [[ -f "$log_file" ]] || fail "Log file not found: $log_file"
    grep -q "$expected_content" "$log_file" || fail "Log file does not contain: $expected_content"
}

# Assert that a directory structure exists
assert_directory_structure() {
    local base_dir="$1"
    shift
    local expected_dirs=("$@")
    
    for dir in "${expected_dirs[@]}"; do
        [[ -d "$base_dir/$dir" ]] || fail "Directory not found: $base_dir/$dir"
    done
}

# Run script with timeout to prevent hanging
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    local cmd=("$@")
    
    timeout "$timeout_seconds" "${cmd[@]}"
}

# Check if a service would be loaded (without actually loading it)
assert_service_plist_valid() {
    local plist_path="$1"
    [[ -f "$plist_path" ]] || fail "Plist not found: $plist_path"
    
    # Check basic XML syntax
    plutil -lint "$plist_path" || fail "Invalid plist syntax: $plist_path"
}

# Utility to check if we're in test mode
is_test_mode() {
    [[ "$TEST_MODE" == "1" ]]
}

# Skip test if not in appropriate test mode
skip_if_not_integration() {
    [[ "$TEST_INTEGRATION" == "1" ]] || skip "Integration tests disabled (set TEST_INTEGRATION=1)"
}

skip_if_not_full_system() {
    [[ "$TEST_FULL_SYSTEM" == "1" ]] || skip "Full system tests disabled (set TEST_FULL_SYSTEM=1)"
}

# Fail function for BATS tests
fail() {
    echo "$1" >&2
    return 1
}
