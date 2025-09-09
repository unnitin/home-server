#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
SUMMARY_OK=()
SUMMARY_WARN=()
SUMMARY_FAIL=()

section(){ echo -e "\n${YELLOW}== $* ==${NC}"; }
ok(){ echo -e "${GREEN}OK${NC}  - $*"; SUMMARY_OK+=("$*"); }
warn(){ echo -e "${YELLOW}WARN${NC} - $*"; SUMMARY_WARN+=("$*"); }
fail(){ echo -e "${RED}FAIL${NC} - $*"; SUMMARY_FAIL+=("$*"); }

require_cmd(){ command -v "$1" >/dev/null 2>&1 || { fail "Missing command: $1"; return 1; }; ok "Found $1"; }

tcp_open(){
  local host="$1" port="$2"
  if nc -z "$host" "$port" >/dev/null 2>&1; then ok "TCP open: $host:$port"; return 0; else warn "TCP closed: $host:$port"; return 1; fi
}

http_probe(){
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    if curl -fsS -m 4 "$url" >/dev/null; then ok "HTTP 200: $url"; return 0; else warn "HTTP not OK: $url"; return 1; fi
  else
    warn "curl not installed; skipping HTTP probe for $url"
  fi
}

print_summary(){
  echo -e "\n${YELLOW}== Summary ==${NC}"
  echo "Passed: ${#SUMMARY_OK[@]}"
  echo "Warnings: ${#SUMMARY_WARN[@]}"
  echo "Failures: ${#SUMMARY_FAIL[@]}"
  if ((${#SUMMARY_FAIL[@]} > 0)); then
    echo -e "\n${RED}Failures:${NC}"; for i in "${SUMMARY_FAIL[@]}"; do echo " - $i"; done
    return 1
  fi
  return 0
}
