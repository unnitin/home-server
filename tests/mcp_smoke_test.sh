#!/usr/bin/env bash
# MCP Server Smoke Test
# Starts the server on a loopback test port, checks it answers MCP, is bound to
# loopback only and rejects foreign Host headers, then shuts it down.
# Usage: bash tests/mcp_smoke_test.sh      (PYTHON=... to pick the interpreter)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_PY="$REPO_ROOT/homelab_mcp/mcp_server.py"
PYTHON="${PYTHON:-python3}"
PORT="${MCP_SMOKE_PORT:-18799}"   # not 18765, so it can run next to the real server
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
}
trap cleanup EXIT

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0"}}}'
post() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 5 -X POST "http://127.0.0.1:$PORT/mcp" \
        -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
        "$@" -d "$INIT"
}

# --- 1. Dependencies present ---
"$PYTHON" -c "import mcp.server.fastmcp, uvicorn, starlette" 2>/dev/null \
    || fail "Missing Python deps: $PYTHON -m pip install -r homelab_mcp/requirements.txt"
pass "Python dependencies available ($PYTHON)"

# --- 2. Server file exists ---
[[ -f "$SERVER_PY" ]] || fail "homelab_mcp/mcp_server.py not found"
pass "homelab_mcp/mcp_server.py exists"

# --- 3. Port is free ---
if lsof -iTCP:"$PORT" -sTCP:LISTEN -t >/dev/null 2>&1; then
    fail "Port $PORT already in use"
fi
pass "Port $PORT is free"

# --- 4. Start server ---
HOMELAB_MCP_PORT="$PORT" "$PYTHON" "$SERVER_PY" >/dev/null 2>&1 &
SERVER_PID=$!
for i in $(seq 1 20); do
    curl -s --max-time 1 -o /dev/null "http://127.0.0.1:$PORT/mcp" && break
    sleep 0.5
    [[ $i -eq 20 ]] && fail "Server did not become ready within 10 seconds"
done
pass "Server started (PID $SERVER_PID)"

# --- 5. Bound to loopback only ---
listeners=$(lsof -nP -a -p "$SERVER_PID" -iTCP -sTCP:LISTEN | awk 'NR > 1 {print $9}')
[[ "$listeners" == "127.0.0.1:$PORT" ]] || fail "Expected only 127.0.0.1:$PORT, got: $listeners"
pass "Listening on 127.0.0.1:$PORT only"

# --- 6. MCP initialize works, for loopback and tailnet Host headers ---
[[ "$(post)" == "200" ]] || fail "initialize via loopback did not return 200"
[[ "$(post -H "Host: mini.example.ts.net:8765")" == "200" ]] || fail "tailnet Host rejected"
pass "MCP initialize returns 200 (loopback and tailnet Host)"

# --- 7. Foreign Host rejected (DNS-rebinding protection) ---
[[ "$(post -H "Host: evil.example.com")" == "421" ]] || fail "foreign Host was not rejected with 421"
pass "Foreign Host header rejected (421)"

# --- 8. Process still alive ---
kill -0 "$SERVER_PID" 2>/dev/null || fail "Server process died unexpectedly"
pass "Server process still alive"

echo ""
echo "All smoke tests passed. MCP server is functional."
