#!/usr/bin/env bash
set -euo pipefail

# Diagnostic Library - Shared functions for homeserver diagnostics
# Provides standardized output, checks, and utilities

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Result tracking arrays
SUMMARY_OK=()
SUMMARY_WARN=()
SUMMARY_FAIL=()

# Output functions with result tracking
section() { 
    echo -e "\n${CYAN}== $* ==${NC}"
}

ok() { 
    echo -e "${GREEN}OK${NC}  - $*"
    SUMMARY_OK+=("$*")
}

warn() { 
    echo -e "${YELLOW}WARN${NC} - $*"
    SUMMARY_WARN+=("$*")
}

fail() { 
    echo -e "${RED}FAIL${NC} - $*"
    SUMMARY_FAIL+=("$*")
}

info() {
    echo -e "${BLUE}INFO${NC} - $*"
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
        return 1
    elif ((${#SUMMARY_WARN[@]} > 0)); then
        return 0  # Warnings don't cause failure
    else
        return 0
    fi
}

# Utility to run a command and capture success/failure
run_check() {
    local description="$1"
    local command="$2"
    local show_output="${3:-false}"
    
    if eval "$command" >/dev/null 2>&1; then
        ok "$description"
        return 0
    else
        if [[ "$show_output" == "true" ]]; then
            local output
            output=$(eval "$command" 2>&1 || true)
            fail "$description"
            if [[ -n "$output" ]]; then
                echo "  Output: $output"
            fi
        else
            fail "$description"
        fi
        return 1
    fi
}

# Clean up function to reset state for new script
reset_diagnostics() {
    SUMMARY_OK=()
    SUMMARY_WARN=()
    SUMMARY_FAIL=()
}