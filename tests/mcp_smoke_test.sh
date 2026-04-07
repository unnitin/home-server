#!/usr/bin/env bash
# MCP Server Smoke Test
# Starts the server, verifies the /mcp endpoint responds, then shuts it down.
# Usage: bash tests/mcp_smoke_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_PY="$REPO_ROOT/mcp/mcp_server.py"
PORT=8765
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
}
trap cleanup EXIT

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; exit 1; }

# --- 1. Dependencies present ---
python3 -c "import mcp, uvicorn, starlette" 2>/dev/null \
    || fail "Missing Python deps — run: pip install -r mcp/requirements.txt"
pass "Python dependencies available"

# --- 2. Server file exists ---
[[ -f "$SERVER_PY" ]] || fail "mcp/mcp_server.py not found"
pass "mcp/mcp_server.py exists"

# --- 3. Port is free ---
if lsof -iTCP:$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    fail "Port $PORT already in use — is the MCP server already running?"
fi
pass "Port $PORT is free"

# --- 4. Start server ---
python3 "$SERVER_PY" &
SERVER_PID=$!

# Wait up to 10s for the server to be ready
for i in $(seq 1 20); do
    if curl -s --max-time 1 -X POST "http://localhost:$PORT/mcp" \
        -H "Content-Type: application/json" \
        -d '{}' -o /dev/null 2>/dev/null; then
        break
    fi
    sleep 0.5
    if [[ $i -eq 20 ]]; then
        fail "Server did not become ready within 10 seconds"
    fi
done
pass "Server started (PID $SERVER_PID)"

# --- 5. MCP endpoint accepts POST and returns SSE stream ---
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
    -X POST "http://localhost:$PORT/mcp" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0"}}}')
[[ "$HTTP_CODE" == "200" ]] \
    || fail "Expected HTTP 200 from /mcp, got: $HTTP_CODE"
pass "MCP endpoint returns HTTP 200"

# --- 6. Process is still alive after requests ---
kill -0 "$SERVER_PID" 2>/dev/null \
    || fail "Server process died unexpectedly"
pass "Server process still alive"

echo ""
echo "All smoke tests passed. MCP server is functional."
