#!/usr/bin/env bats

load '../test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "scripts do not contain hardcoded credentials" {
    # Test that no scripts contain obvious credential patterns
    # Excludes safe patterns like environment variables and documentation examples
    local credential_patterns=(
        'password="[^$]'      # password= followed by non-variable
        'api_key="[^$]'       # api_key= followed by non-variable
        'secret="[^$]'        # secret= followed by non-variable
        'token="[^$]'         # token= followed by non-variable
    )
    
    for pattern in "${credential_patterns[@]}"; do
        run grep -riE "$pattern" scripts/
        if [ "$status" -eq 0 ]; then
            # Filter out safe patterns
            local filtered_output=$(echo "$output" | grep -vE "(IMMICH_DB_PASSWORD|example|your-api-key|your-password|\\\$\{|:-\})")
            if [[ -n "$filtered_output" ]]; then
                fail "Found potential hardcoded credential: $pattern in $filtered_output"
            fi
        fi
    done
}

@test "scripts properly validate sudo requirements" {
    # Test that scripts requiring sudo check permissions appropriately
    local sudo_scripts=(
        "scripts/storage/ensure_mounts.sh"
        "scripts/automation/configure_launchd.sh"
        "scripts/infrastructure/configure_power.sh"
    )
    
    for script in "${sudo_scripts[@]}"; do
        if [[ -f "$script" ]]; then
            run grep -q "sudo\|EUID" "$script"
            [ "$status" -eq 0 ] || fail "Script $script should check for sudo/root permissions"
        fi
    done
}

@test "scripts do not execute dangerous commands without validation" {
    # Test that destructive operations require explicit confirmation
    local dangerous_patterns=(
        "rm -rf /"
        "dd if="
        "mkfs"
        "diskutil.*erase"
    )
    
    for pattern in "${dangerous_patterns[@]}"; do
        run grep -r "$pattern" scripts/
        if [ "$status" -eq 0 ]; then
            # Should have safety checks nearby
            local file_with_pattern=$(echo "$output" | cut -d: -f1 | head -1)
            run grep -B5 -A5 "$pattern" "$file_with_pattern"
            [[ "$output" =~ RAID_I_UNDERSTAND_DATA_LOSS|confirm|read.*-p ]] || \
                fail "Dangerous command '$pattern' in $file_with_pattern lacks safety validation"
        fi
    done
}

@test "LaunchD services run with appropriate user permissions" {
    # Test that LaunchD services don't run as root unnecessarily
    local plist_files=(launchd/*.plist)
    
    for plist in "${plist_files[@]}"; do
        if [[ -f "$plist" ]]; then
            # Should not contain UserName root unless necessary
            if grep -q "<key>UserName</key>" "$plist"; then
                run grep -A1 "<key>UserName</key>" "$plist"
                [[ "$output" =~ "root" ]] && fail "Service $plist runs as root - verify if necessary"
            fi
        fi
    done
}

@test "scripts validate input parameters" {
    # Test that scripts properly validate their inputs
    local scripts_with_params=(
        "scripts/media/process_movie.sh"
        "scripts/media/process_tv_show.sh"
        "scripts/storage/cleanup_disks.sh"
    )
    
    for script in "${scripts_with_params[@]}"; do
        if [[ -f "$script" ]]; then
            # Should have parameter validation
            run grep -E "\[\[ -z.*\]\]|\[\[ \$# -" "$script"
            [ "$status" -eq 0 ] || fail "Script $script should validate input parameters"
        fi
    done
}
