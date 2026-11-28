#!/usr/bin/env bash
set -euo pipefail

# Diagnostic Library - Shared functions for homeserver diagnostics
# Provides standardized output, checks, and utilities

# The manifest's values (tier mounts, ports, health URLs), from config/homelab.env,
# the file generated from config/homelab.yaml. Read directly, not through
# scripts/core/environment.sh: diagnostics depend on nothing in scripts/. A
# HOMELAB_* value the caller set wins; without the file, each diagnostic falls
# back to its built-in default.
_diag_load_manifest() {
    local env_file saved=() name kv
    env_file="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/config/homelab.env"
    [[ -f "$env_file" ]] || return 0
    while IFS= read -r name; do
        saved+=("$name=${!name}")
    done < <(compgen -v | grep '^HOMELAB_' || true)
    set -a
    # shellcheck source=../config/homelab.env
    source "$env_file"
    set +a
    for kv in ${saved[@]+"${saved[@]}"}; do
        export "${kv%%=*}=${kv#*=}"
    done
}
_diag_load_manifest

# The mount point of a storage tier from the manifest, or the default given
diag_tier_mount() {  # diag_tier_mount TIER DEFAULT
    local var
    var="HOMELAB_TIER_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_MOUNT"
    printf '%s\n' "${!var:-$2}"
}

# True when a volume is mounted exactly at PATH. A folder under /Volumes is not
# proof: macOS leaves empty mount-point folders behind, and df on one reports
# the internal disk (D22). Only diskutil knows. (A copy of
# scripts/core/environment.sh's homelab_is_mounted: diagnostics source nothing
# from scripts/.)
diag_is_mounted() {
    local mount_point
    mount_point=$(diskutil info -plist "${1:-}" 2>/dev/null |
        plutil -extract MountPoint raw -o - - 2>/dev/null) || return 1
    [[ -n "$mount_point" && "$mount_point" == "${1:-}" ]]
}

# Color definitions. Disabled when NO_COLOR is set or stdout isn't a terminal
# (e.g. output captured by the MCP server), so callers never get escape codes.
if [[ -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
else
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m' # No Color
fi

# Result tracking arrays
SUMMARY_OK=()
SUMMARY_WARN=()
SUMMARY_FAIL=()

# Output format. text (the default) is for people. json (DIAG_FORMAT=json) is
# for the MCP server: stdout carries JSON Lines, one object per check
#   {"type":"check","id":"immich.main.1","component":"immich","section":"",
#    "status":"ok","message":"HTTP 200 /api/server/ping"}
# plus {"type":"info",...} lines and one final
#   {"type":"summary","component":"immich","status":"ok","summary":"...",
#    "passed":1,"warnings":0,"failures":0,"exit_code":0}
# Everything else a script prints goes to stderr, so stdout stays valid JSON
# even for scripts that echo directly. Diagnostics started by another one
# (run_all.sh) write to the same JSON stream, inherited on fd 3.
DIAG_FORMAT="${DIAG_FORMAT:-text}"
DIAG_SECTION=""
DIAG_SEQ=0
DIAG_SUMMARY_DONE=0

# The health_check component a script reports as (03-tool-catalog.md). A
# script may set DIAG_COMPONENT before sourcing this file.
_diag_default_component() {
    local name
    name="$(basename "$0" .sh)"
    case "$name" in
        check_plex_native) echo plex ;;
        check_raid_status) echo raid ;;
        check_colima_docker | check_docker_services) echo docker ;;
        check_remote_access) echo tailscale ;;
        check_power_settings) echo power ;;
        check_storage | verify_media_paths) echo storage ;;
        network_port_check) echo network ;;
        run_all | full_summary) echo all ;;
        collect_logs) echo logs ;;
        check_*) echo "${name#check_}" ;;
        *) echo "$name" ;;
    esac
}
DIAG_COMPONENT="${DIAG_COMPONENT:-$(_diag_default_component)}"

# A JSON string literal, quotes included.
_diag_json_str() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    # Any other control character (an escape code, say) is dropped.
    s=$(printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037')
    printf '"%s"' "$s"
}

_diag_slug() {
    local s
    s=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
    s="${s#-}"
    s="${s%-}"
    printf '%s' "${s:-main}"
}

_diag_emit() {
    [[ "$DIAG_FORMAT" == json ]] || return 0
    printf '%s\n' "$1" >&3
}

# _diag_check STATUS MESSAGE
_diag_check() {
    DIAG_SEQ=$((DIAG_SEQ + 1))
    _diag_emit "{\"type\":\"check\",\"id\":$(_diag_json_str "$DIAG_COMPONENT.$(_diag_slug "$DIAG_SECTION").$DIAG_SEQ"),\"component\":$(_diag_json_str "$DIAG_COMPONENT"),\"section\":$(_diag_json_str "$DIAG_SECTION"),\"status\":\"$1\",\"message\":$(_diag_json_str "$2")}"
}

_diag_summary_record() {
    local exit_code="${1:-0}" status
    local passed=${#SUMMARY_OK[@]} warnings=${#SUMMARY_WARN[@]} failures=${#SUMMARY_FAIL[@]}
    if ((failures > 0)); then
        status=fail
    elif ((exit_code != 0)); then
        status=error
    elif ((warnings > 0)); then
        status=warn
    elif ((passed > 0)); then
        status=ok
    else
        status=unknown
    fi
    DIAG_SUMMARY_DONE=1
    _diag_emit "{\"type\":\"summary\",\"component\":$(_diag_json_str "$DIAG_COMPONENT"),\"status\":\"$status\",\"summary\":$(_diag_json_str "$DIAG_COMPONENT: $passed passed, $warnings warnings, $failures failures"),\"passed\":$passed,\"warnings\":$warnings,\"failures\":$failures,\"exit_code\":$exit_code}"
}

# A script that exits without print_summary (an early exit, set -e) still ends
# its JSON stream with a summary. Scripts sourcing this file must not set their
# own EXIT trap.
_diag_json_finish() {
    local exit_code="$1"
    ((DIAG_SUMMARY_DONE)) || _diag_summary_record "$exit_code"
}

if [[ "$DIAG_FORMAT" == json ]]; then
    if [[ "${DIAG_JSON_FD_READY:-}" != 1 ]]; then
        exec 3>&1
        export DIAG_JSON_FD_READY=1
    fi
    exec 1>&2
    trap '_diag_json_finish "$?"' EXIT
fi

# Output functions with result tracking
section() {
    DIAG_SECTION="$*"
    echo -e "\n${CYAN}== $* ==${NC}"
}

ok() {
    echo -e "${GREEN}OK${NC}  - $*"
    SUMMARY_OK+=("$*")
    _diag_check ok "$*"
}

warn() {
    echo -e "${YELLOW}WARN${NC} - $*"
    SUMMARY_WARN+=("$*")
    _diag_check warn "$*"
}

fail() {
    echo -e "${RED}FAIL${NC} - $*"
    SUMMARY_FAIL+=("$*")
    _diag_check fail "$*"
}

info() {
    echo -e "${BLUE}INFO${NC} - $*"
    _diag_emit "{\"type\":\"info\",\"component\":$(_diag_json_str "$DIAG_COMPONENT"),\"section\":$(_diag_json_str "$DIAG_SECTION"),\"message\":$(_diag_json_str "$*")}"
}

# Record a result without printing it, for scripts with their own output
# format: diag_record ok|warn|fail MESSAGE
diag_record() {
    case "$1" in
        ok) SUMMARY_OK+=("$2") ;;
        warn) SUMMARY_WARN+=("$2") ;;
        fail) SUMMARY_FAIL+=("$2") ;;
        *) return 1 ;;
    esac
    _diag_check "$1" "$2"
}

# Command existence check
require_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "Found $1"
        return 0
    else
        fail "Missing command: $1"
        return 1
    fi
}

# TCP port connectivity test
tcp_open() {
    local host="$1"
    local port="$2"

    if command -v nc >/dev/null 2>&1; then
        if nc -z "$host" "$port" >/dev/null 2>&1; then
            ok "TCP open: $host:$port"
            return 0
        else
            warn "TCP closed: $host:$port"
            return 1
        fi
    else
        warn "netcat (nc) not available; skipping TCP test for $host:$port"
        return 1
    fi
}

# HTTP/HTTPS connectivity test
http_probe() {
    local url="$1"
    local timeout="${2:-4}"

    if command -v curl >/dev/null 2>&1; then
        if curl -fsS -m "$timeout" "$url" >/dev/null 2>&1; then
            ok "HTTP 200: $url"
            return 0
        else
            warn "HTTP not OK: $url"
            return 1
        fi
    else
        warn "curl not installed; skipping HTTP probe for $url"
        return 1
    fi
}

# Check if a process is running
check_process() {
    local process_name="$1"
    local description="${2:-$process_name}"

    if pgrep -f "$process_name" >/dev/null 2>&1; then
        ok "$description process running"
        return 0
    else
        fail "$description process not running"
        return 1
    fi
}

# Check if a service is loaded in launchctl
check_launchd_service() {
    local service_label="$1"
    local description="${2:-$service_label}"

    if launchctl print "system/$service_label" >/dev/null 2>&1 || launchctl print "gui/$(id -u)/$service_label" >/dev/null 2>&1; then
        ok "$description LaunchD service loaded"
        return 0
    else
        warn "$description LaunchD service not loaded"
        return 1
    fi
}

# Check file or directory existence
check_path() {
    local path="$1"
    local description="${2:-$path}"
    local type="${3:-file}" # file, dir, or any

    case "$type" in
        "file")
            if [[ -f "$path" ]]; then
                ok "$description exists"
                return 0
            else
                fail "$description not found"
                return 1
            fi
            ;;
        "dir")
            if [[ -d "$path" ]]; then
                ok "$description exists"
                return 0
            else
                fail "$description not found"
                return 1
            fi
            ;;
        "any")
            if [[ -e "$path" ]]; then
                ok "$description exists"
                return 0
            else
                fail "$description not found"
                return 1
            fi
            ;;
        *)
            fail "Invalid path type: $type"
            return 1
            ;;
    esac
}

# Check write permissions
check_writable() {
    local path="$1"
    local description="${2:-$path}"

    if [[ -w "$path" ]]; then
        ok "$description is writable"
        return 0
    else
        warn "$description is not writable"
        return 1
    fi
}

# Check disk usage and warn if high
check_disk_usage() {
    local mount_point="$1"
    local warn_threshold="${2:-80}"
    local critical_threshold="${3:-90}"

    if [[ -d "$mount_point" ]] && df "$mount_point" >/dev/null 2>&1; then
        local usage_info=$(df -h "$mount_point" | tail -1)
        local usage_percent=$(echo "$usage_info" | awk '{print $5}' | sed 's/%//')
        local used=$(echo "$usage_info" | awk '{print $3}')
        local available=$(echo "$usage_info" | awk '{print $4}')

        if [[ $usage_percent -ge $critical_threshold ]]; then
            fail "Critical disk usage: $usage_percent% ($used used, $available available)"
            return 1
        elif [[ $usage_percent -ge $warn_threshold ]]; then
            warn "High disk usage: $usage_percent% ($used used, $available available)"
            return 1
        else
            ok "Disk usage OK: $usage_percent% ($used used, $available available)"
            return 0
        fi
    else
        fail "Cannot check disk usage for $mount_point"
        return 1
    fi
}

# Version comparison utility
version_compare() {
    local version1="$1"
    local operator="$2"
    local version2="$3"

    # Simple version comparison (works for most cases)
    case "$operator" in
        ">="|"ge")
            [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version2" ]]
            ;;
        ">"|"gt")
            [[ "$version1" != "$version2" ]] && [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | head -n1)" == "$version2" ]]
            ;;
        "<="|"le")
            [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | tail -n1)" == "$version2" ]]
            ;;
        "<"|"lt")
            [[ "$version1" != "$version2" ]] && [[ "$(printf '%s\n' "$version1" "$version2" | sort -V | tail -n1)" == "$version2" ]]
            ;;
        "=="|"eq")
            [[ "$version1" == "$version2" ]]
            ;;
        "!="|"ne")
            [[ "$version1" != "$version2" ]]
            ;;
        *)
            fail "Invalid version comparison operator: $operator"
            return 1
            ;;
    esac
}

# Summary and exit handling
print_summary() {
    echo -e "\n${CYAN}== Summary ==${NC}"
    echo "Passed: ${#SUMMARY_OK[@]}"
    echo "Warnings: ${#SUMMARY_WARN[@]}"
    echo "Failures: ${#SUMMARY_FAIL[@]}"

    if ((${#SUMMARY_FAIL[@]} > 0)); then
        echo -e "\n${RED}Failures:${NC}"
        for failure in "${SUMMARY_FAIL[@]}"; do
            echo "  - $failure"
        done
    fi

    if ((${#SUMMARY_WARN[@]} > 0)); then
        echo -e "\n${YELLOW}Warnings:${NC}"
        for warning in "${SUMMARY_WARN[@]}"; do
            echo "  - $warning"
        done
    fi

    # Return appropriate exit code
    if ((${#SUMMARY_FAIL[@]} > 0)); then
        _diag_summary_record 1
        return 1
    fi
    _diag_summary_record 0
    return 0 # warnings don't cause failure
}

# Run a command and record OK/FAIL. The command is an argv list, never a string,
# so nothing is ever passed through eval.
# Usage: run_check "description" [--show-output] cmd [args...]
run_check() {
    local description="$1"
    shift
    local show_output=false
    if [[ "${1:-}" == "--show-output" ]]; then
        show_output=true
        shift
    fi

    local output
    if output=$("$@" 2>&1); then
        ok "$description"
        return 0
    fi
    fail "$description"
    if $show_output && [[ -n "$output" ]]; then
        echo "  Output: $output"
    fi
    return 1
}

# Clean up function to reset state for new script
reset_diagnostics() {
    SUMMARY_OK=()
    SUMMARY_WARN=()
    SUMMARY_FAIL=()
    DIAG_SECTION=""
    DIAG_SEQ=0
    DIAG_SUMMARY_DONE=0
}
