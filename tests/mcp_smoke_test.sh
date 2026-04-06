#!/usr/bin/env bash
# MCP Server Smoke Test
# Starts the server, verifies the SSE endpoint responds, then shuts it down.
# Usage: bash tests/mcp_smoke_test.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_PY="$REPO_ROOT/mcp/server.py"
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
[[ -f "$SERVER_PY" ]] || fail "mcp/server.py not found"
pass "mcp/server.py exists"

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
    if curl -s --max-time 1 "http://localhost:$PORT/sse" -o /dev/null 2>/dev/null; then
        break
    fi
    sleep 0.5
    if [[ $i -eq 20 ]]; then
        fail "Server did not become ready within 10 seconds"
    fi
done
pass "Server started (PID $SERVER_PID)"

# --- 5. SSE endpoint returns correct content-type ---
CONTENT_TYPE=$(curl -s -I --max-time 5 "http://localhost:$PORT/sse" \
    | grep -i "content-type" | head -1)
echo "$CONTENT_TYPE" | grep -qi "text/event-stream" \
    || fail "Expected text/event-stream content-type, got: $CONTENT_TYPE"
pass "SSE endpoint returns text/event-stream"

# --- 6. Process is still alive after requests ---
kill -0 "$SERVER_PID" 2>/dev/null \
    || fail "Server process died unexpectedly"
pass "Server process still alive"

echo ""
echo "All smoke tests passed. MCP server is functional."