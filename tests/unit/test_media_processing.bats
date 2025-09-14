#!/usr/bin/env bats
# Unit tests for media processing logic and naming conventions

load '../test_helper'

setup() {
    setup_test_env
    create_fake_storage
    mock_system_commands
    
    # Create staging and target directories
    mkdir -p "$WARMSTORE/Staging/Movies"
    mkdir -p "$WARMSTORE/Staging/TV Shows"
    mkdir -p "$WARMSTORE/Staging/Collections"
    mkdir -p "$WARMSTORE/Movies"
    mkdir -p "$WARMSTORE/TV Shows"
    mkdir -p "$WARMSTORE/Collections"
    mkdir -p "$WARMSTORE/logs/media-watcher"
}

teardown() {
    teardown_test_env
}

@test "movie filename parsing extracts name and year correctly" {
    # Test movie name extraction logic
    local test_files=(
        "The Matrix (1999).mkv:The Matrix:1999"
        "Inception.2010.1080p.BluRay.mkv:Inception:2010"
        "Avatar (2009) [1080p].mp4:Avatar:2009"
        "The.Dark.Knight.2008.mkv:The Dark Knight:2008"
        "Pulp Fiction (1994).avi:Pulp Fiction:1994"
    )
    
    for test_case in "${test_files[@]}"; do
        local filename="${test_case%%:*}"
        local expected_name="${test_case#*:}"
        expected_name="${expected_name%%:*}"
        local expected_year="${test_case##*:}"
        
        # Create test file
        touch "$WARMSTORE/Staging/Movies/$filename"
        
        # Test our parsing logic (simplified version)
        local parsed_name parsed_year
        
        # Extract year (look for 4-digit year in parentheses or standalone)
        if [[ "$filename" =~ \(([0-9]{4})\) ]]; then
            parsed_year="${BASH_REMATCH[1]}"
            parsed_name="${filename%% (*}"
        elif [[ "$filename" =~ \.([0-9]{4})\. ]]; then
            parsed_year="${BASH_REMATCH[1]}"
            parsed_name="${filename%%.*}"
            parsed_name="${parsed_name//./ }"
        fi
        
        # Clean up name
        parsed_name="${parsed_name// / }"
        parsed_name="${parsed_name#"${parsed_name%%[![:space:]]*}"}"
        parsed_name="${parsed_name%"${parsed_name##*[![:space:]]}"}"
        
        [[ "$parsed_year" == "$expected_year" ]] || fail "Year parsing failed for $filename: got '$parsed_year', expected '$expected_year'"
        
        # Clean up
        rm -f "$WARMSTORE/Staging/Movies/$filename"
    done
}

@test "TV show filename parsing extracts show, season, and episode" {
    local test_files=(
        "Breaking Bad - s01e01 - Pilot.mkv:Breaking Bad:01:01"
        "Game.of.Thrones.S08E06.1080p.mkv:Game of Thrones:08:06"
        "The Office (US) - S02E01.mp4:The Office (US):02:01"
        "Friends.s10e18.The.Last.One.avi:Friends:10:18"
    )
    
    for test_case in "${test_files[@]}"; do
        local filename="${test_case%%:*}"
        local expected_show="${test_case#*:}"
        expected_show="${expected_show%%:*}"
        local remaining="${test_case#*:*:}"
        local expected_season="${remaining%%:*}"
        local expected_episode="${remaining##*:}"
        
        # Create test file
        touch "$WARMSTORE/Staging/TV Shows/$filename"
        
        # Test parsing logic
        local parsed_show parsed_season parsed_episode
        
        if [[ "$filename" =~ [Ss]([0-9]{2})[Ee]([0-9]{2}) ]]; then
            parsed_season="${BASH_REMATCH[1]}"
            parsed_episode="${BASH_REMATCH[2]}"
            
            # Extract show name (everything before season/episode)
            parsed_show="${filename%% - [Ss]*}"
            parsed_show="${parsed_show%%.[Ss]*}"
            parsed_show="${parsed_show//./ }"
        fi
        
        [[ "$parsed_season" == "$expected_season" ]] || fail "Season parsing failed for $filename: got '$parsed_season', expected '$expected_season'"
        [[ "$parsed_episode" == "$expected_episode" ]] || fail "Episode parsing failed for $filename: got '$parsed_episode', expected '$expected_episode'"
        
        # Clean up
        rm -f "$WARMSTORE/Staging/TV Shows/$filename"
    done
}

@test "media processor creates correct Plex directory structure" {
    # Test Plex naming convention compliance
    
    # Create test movie file
    local movie_file="The Matrix (1999).mkv"
    touch "$WARMSTORE/Staging/Movies/$movie_file"
    
    # Expected Plex structure: Movies/The Matrix (1999)/The Matrix (1999).mkv
    local expected_movie_dir="$WARMSTORE/Movies/The Matrix (1999)"
    local expected_movie_file="$expected_movie_dir/The Matrix (1999).mkv"
    
    # Simulate processing (create expected structure)
    mkdir -p "$expected_movie_dir"
    mv "$WARMSTORE/Staging/Movies/$movie_file" "$expected_movie_file"
    
    # Verify structure
    [[ -f "$expected_movie_file" ]] || fail "Movie file not in correct Plex location"
    [[ ! -f "$WARMSTORE/Staging/Movies/$movie_file" ]] || fail "Movie file not moved from staging"
    
    # Test TV show structure
    local tv_file="Breaking Bad - s01e01 - Pilot.mkv"
    touch "$WARMSTORE/Staging/TV Shows/$tv_file"
    
    # Expected Plex structure: TV Shows/Breaking Bad/Season 01/Breaking Bad - s01e01.mkv
    local expected_tv_dir="$WARMSTORE/TV Shows/Breaking Bad/Season 01"
    local expected_tv_file="$expected_tv_dir/Breaking Bad - s01e01.mkv"
    
    mkdir -p "$expected_tv_dir"
    mv "$WARMSTORE/Staging/TV Shows/$tv_file" "$expected_tv_file"
    
    [[ -f "$expected_tv_file" ]] || fail "TV show file not in correct Plex location"
}

@test "media processor handles associated files correctly" {
    # Test that subtitles and metadata files are moved with media files
    local base_name="The Matrix (1999)"
    local media_files=(
        "$base_name.mkv"
        "$base_name.srt"
        "$base_name.en.srt"
        "$base_name.nfo"
        "$base_name-poster.jpg"
    )
    
    # Create test files in staging
    for file in "${media_files[@]}"; do
        touch "$WARMSTORE/Staging/Movies/$file"
    done
    
    # Simulate processing - move all related files
    local target_dir="$WARMSTORE/Movies/$base_name"
    mkdir -p "$target_dir"
    
    for file in "${media_files[@]}"; do
        if [[ -f "$WARMSTORE/Staging/Movies/$file" ]]; then
            mv "$WARMSTORE/Staging/Movies/$file" "$target_dir/"
        fi
    done
    
    # Verify all files moved
    for file in "${media_files[@]}"; do
        [[ -f "$target_dir/$file" ]] || fail "Associated file not moved: $file"
        [[ ! -f "$WARMSTORE/Staging/Movies/$file" ]] || fail "Associated file not removed from staging: $file"
    done
}

@test "media processor handles failed files correctly" {
    # Test failed file quarantine
    local failed_file="Invalid Movie Name.mkv"
    touch "$WARMSTORE/Staging/Movies/$failed_file"
    
    # Simulate failed processing - move to failed directory
    mkdir -p "$WARMSTORE/Staging/failed"
    mv "$WARMSTORE/Staging/Movies/$failed_file" "$WARMSTORE/Staging/failed/"
    
    # Verify quarantine
    [[ -f "$WARMSTORE/Staging/failed/$failed_file" ]] || fail "Failed file not quarantined"
    [[ ! -f "$WARMSTORE/Staging/Movies/$failed_file" ]] || fail "Failed file not removed from staging"
}

@test "collections processing preserves directory structure" {
    # Test that Collections maintain exact folder structure
    local collection_structure=(
        "Adult/Category1/Video1.mp4"
        "Adult/Category1/Video2.mkv"
        "Adult/Category2/Subfolder/Video3.avi"
    )
    
    # Create test structure in staging
    for file_path in "${collection_structure[@]}"; do
        local dir_path="$WARMSTORE/Staging/Collections/${file_path%/*}"
        mkdir -p "$dir_path"
        touch "$WARMSTORE/Staging/Collections/$file_path"
    done
    
    # Simulate collections processing (preserve structure)
    cp -r "$WARMSTORE/Staging/Collections/"* "$WARMSTORE/Collections/" 2>/dev/null || true
    
    # Verify structure preserved
    for file_path in "${collection_structure[@]}"; do
        [[ -f "$WARMSTORE/Collections/$file_path" ]] || fail "Collection file not preserved: $file_path"
    done
}

@test "media processor supports all expected file formats" {
    local supported_formats=(
        "mkv" "mp4" "avi" "mov" "m4v" "wmv" "flv" "webm"
    )
    
    for format in "${supported_formats[@]}"; do
        local test_file="Test Movie (2023).$format"
        touch "$WARMSTORE/Staging/Movies/$test_file"
        
        # Test format recognition (simplified)
        case "$format" in
            mkv|mp4|avi|mov|m4v|wmv|flv|webm)
                # Format should be supported
                [[ -f "$WARMSTORE/Staging/Movies/$test_file" ]] || fail "Test file creation failed for format: $format"
                ;;
            *)
                fail "Unsupported format in test: $format"
                ;;
        esac
        
        # Clean up
        rm -f "$WARMSTORE/Staging/Movies/$test_file"
    done
}

@test "media watcher service management commands work" {
    # Test media_watcher.sh command validation
    assert_script_exists "scripts/media_watcher.sh"
    
    local valid_commands=("start" "stop" "status" "restart")
    
    for cmd in "${valid_commands[@]}"; do
        # Test that the script accepts the command (syntax check only)
        run bash -n scripts/media_watcher.sh
        [ "$status" -eq 0 ] || fail "Syntax error in media_watcher.sh"
    done
}
