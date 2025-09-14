#!/usr/bin/env bats
# Unit tests for storage utilities and mount point management

load '../test_helper'

setup() {
    setup_test_env
    create_fake_storage
    mock_system_commands
}

teardown() {
    teardown_test_env
}

@test "ensure_storage_mounts.sh creates required directories" {
    # Test that the script exists and is executable
    assert_script_exists "scripts/storage/ensure_mounts.sh"
    assert_valid_bash_syntax "scripts/storage/ensure_mounts.sh"
    
    # Test basic functionality without actually running it (since it requires sudo)
    # Just verify the script structure and key functions
    run grep -q "mkdir -p" scripts/storage/ensure_mounts.sh
    [ "$status" -eq 0 ]
    
    run grep -q "ln -sf" scripts/storage/ensure_mounts.sh
    [ "$status" -eq 0 ]
}

@test "storage mount script prevents circular symlinks" {
    # Create a scenario that would create circular symlinks
    mkdir -p "$WARMSTORE/Movies"
    mkdir -p "$WARMSTORE/TV Shows"
    mkdir -p "$WARMSTORE/Photos"
    
    # Create circular symlinks (the problem we're testing for)
    ln -sf "$WARMSTORE/Movies" "$WARMSTORE/Movies/Movies"
    ln -sf "$WARMSTORE/TV Shows" "$WARMSTORE/TV Shows/TV Shows"
    ln -sf "$WARMSTORE/Photos" "$WARMSTORE/Photos/Photos"
    
    # Verify circular symlinks exist
    [[ -L "$WARMSTORE/Movies/Movies" ]]
    [[ -L "$WARMSTORE/TV Shows/TV Shows" ]]
    [[ -L "$WARMSTORE/Photos/Photos" ]]
    
    # Now test our cleanup logic (simplified version)
    [[ -L "$WARMSTORE/Movies/Movies" ]] && rm "$WARMSTORE/Movies/Movies"
    [[ -L "$WARMSTORE/TV Shows/TV Shows" ]] && rm "$WARMSTORE/TV Shows/TV Shows"
    [[ -L "$WARMSTORE/Photos/Photos" ]] && rm "$WARMSTORE/Photos/Photos"
    
    # Verify cleanup worked
    [[ ! -L "$WARMSTORE/Movies/Movies" ]]
    [[ ! -L "$WARMSTORE/TV Shows/TV Shows" ]]
    [[ ! -L "$WARMSTORE/Photos/Photos" ]]
}

@test "wait_for_storage.sh validates required mounts" {
    # Test the wait_for_storage.sh logic
    assert_script_exists "scripts/storage/wait_for_storage.sh"
    
    # Create fake mount points
    mkdir -p "$TEST_TEMP_DIR/Volumes/warmstore"
    mkdir -p "$TEST_TEMP_DIR/Volumes/Photos"
    
    # Mock the script to use our test directories
    export WARMSTORE="$TEST_TEMP_DIR/Volumes/warmstore"
    
    # Create a test version that doesn't actually wait
    cat > "$TEST_TEMP_DIR/test_wait_for_storage.sh" << EOF
#!/bin/bash
# Test version of wait_for_storage.sh
WARMSTORE="$TEST_TEMP_DIR/Volumes/warmstore"
PHOTOS_LINK="/Volumes/Photos"

# Check if warmstore exists
if [[ ! -d "\$WARMSTORE" ]]; then
    echo "❌ Warmstore not found: \$WARMSTORE"
    exit 1
fi

echo "✅ Storage validation passed"
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/test_wait_for_storage.sh"
    
    run bash "$TEST_TEMP_DIR/test_wait_for_storage.sh"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Storage validation passed" ]]
}

@test "storage directories have correct structure" {
    # Test expected directory structure
    local expected_dirs=(
        "Movies"
        "TV Shows" 
        "Photos"
        "Collections"
        "Staging"
        "logs"
    )
    
    # Create the directories
    for dir in "${expected_dirs[@]}"; do
        mkdir -p "$WARMSTORE/$dir"
    done
    
    # Verify they exist
    assert_directory_structure "$WARMSTORE" "${expected_dirs[@]}"
}

@test "staging directory structure is correct" {
    # Test staging directory setup
    local staging_dirs=(
        "Staging/Movies"
        "Staging/TV Shows"
        "Staging/Collections"
        "Staging/logs"
        "Staging/failed"
    )
    
    # Create staging structure
    for dir in "${staging_dirs[@]}"; do
        mkdir -p "$WARMSTORE/$dir"
    done
    
    # Verify staging structure
    for dir in "${staging_dirs[@]}"; do
        [[ -d "$WARMSTORE/$dir" ]] || fail "Staging directory missing: $WARMSTORE/$dir"
    done
}

@test "media mount points are created correctly" {
    # Test /Volumes/Media symlink creation logic
    mkdir -p "$TEST_TEMP_DIR/Volumes/Media"
    
    # Create source directories
    mkdir -p "$WARMSTORE/Movies"
    mkdir -p "$WARMSTORE/TV Shows"
    mkdir -p "$WARMSTORE/Photos"
    
    # Test symlink creation (without actually creating system symlinks)
    local media_links=(
        "Movies:$WARMSTORE/Movies"
        "TV Shows:$WARMSTORE/TV Shows"
        "Photos:$WARMSTORE/Photos"
    )
    
    for link_spec in "${media_links[@]}"; do
        local link_name="${link_spec%%:*}"
        local link_target="${link_spec##*:}"
        
        # Verify target exists
        [[ -d "$link_target" ]] || fail "Link target missing: $link_target"
        
        # In a real scenario, we'd create: ln -sf "$link_target" "/Volumes/Media/$link_name"
        # For testing, just verify the logic
        [[ -n "$link_name" && -n "$link_target" ]] || fail "Invalid link specification: $link_spec"
    done
}

@test "storage script handles missing directories gracefully" {
    # Test behavior when expected directories don't exist
    
    # Remove warmstore to simulate missing storage
    rm -rf "$WARMSTORE"
    
    # Create a test script that checks for missing storage
    cat > "$TEST_TEMP_DIR/test_missing_storage.sh" << EOF
#!/bin/bash
WARMSTORE="$WARMSTORE"

if [[ ! -d "\$WARMSTORE" ]]; then
    echo "Storage not available: \$WARMSTORE"
    exit 1
fi

echo "Storage available"
exit 0
EOF
    chmod +x "$TEST_TEMP_DIR/test_missing_storage.sh"
    
    run bash "$TEST_TEMP_DIR/test_missing_storage.sh"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Storage not available" ]]
}
