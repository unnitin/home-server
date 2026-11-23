#!/usr/bin/env bats
# Tests the real extract_movie_info() from scripts/media/process_movie.sh
# (test_media_processing.bats only checks a simplified copy of the logic).

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/media/process_movie.sh"
}

# Source the script in a child bash (so its `set -euo pipefail` stays there)
# and print "title|year" for one filename.
parse() {
    bash -c 'source "$1" && extract_movie_info "$2"' _ "$SCRIPT" "$1"
}

check() {
    local filename="$1" expected="$2" got
    got="$(parse "$filename")"
    if [[ "$got" != "$expected" ]]; then
        echo "parse('$filename') = '$got', expected '$expected'" >&2
        return 1
    fi
}

@test "sourcing process_movie.sh does not run it" {
    run bash -c 'source "$1" && echo sourced-ok' _ "$SCRIPT"
    [ "$status" -eq 0 ]
    [ "$output" = "sourced-ok" ]
}

@test "quality tags such as 1080p and 2160p are never read as the year" {
    check "Dune.2021.2160p.WEB-DL.mkv" "Dune|2021"
    check "Inception.2010.1080p.BluRay.mkv" "Inception|2010"
    check "Amelie 2001 1080p BluRay.mkv" "Amelie|2001"
    check "The.Matrix.1999.720p.BluRay.mkv" "The Matrix|1999"
}

@test "a year that is part of the title stays in the title" {
    check "Blade.Runner.2049.2017.1080p.BluRay.x264.mkv" "Blade Runner 2049|2017"
    check "2001.A.Space.Odyssey.1968.1080p.mkv" "2001 A Space Odyssey|1968"
    check "1917.2019.2160p.UHD.mkv" "1917|2019"
}

@test "the year before release tags wins over a later one" {
    check "Some.Film.2010.REMASTERED.2023.1080p.mkv" "Some Film|2010"
}

@test "Plex-style names are kept as written" {
    check "The Matrix (1999).mkv" "The Matrix|1999"
    check "Avatar (2009) [1080p].mp4" "Avatar|2009"
    check "Pulp Fiction (1994).avi" "Pulp Fiction|1994"
}

@test "dot-separated names without quality tags" {
    check "The.Dark.Knight.2008.mkv" "The Dark Knight|2008"
    check "Heat_1995.mkv" "Heat|1995"
}

@test "no year: title is everything before the release tags" {
    check "1917.mkv" "1917|"
    check "Some.Home.Video.1080p.mp4" "Some Home Video|"
}
