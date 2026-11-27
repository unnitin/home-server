#!/usr/bin/env python3
"""Server-level tests for homelab_mcp/mcp_server.py (needs the MCP SDK, mcp<2)."""

import asyncio
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

pytest.importorskip("mcp.server.fastmcp")
from starlette.testclient import TestClient  # noqa: E402

REPO_ROOT = Path(__file__).parent.parent.parent
SERVER = REPO_ROOT / "homelab_mcp" / "mcp_server.py"
sys.path.insert(0, str(REPO_ROOT / "homelab_mcp"))

import mcp_routing  # noqa: E402
import mcp_server  # noqa: E402

INIT = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "pytest", "version": "1"},
    },
}
MCP_HEADERS = {"accept": "application/json, text/event-stream"}


def post_init(client, **headers):
    return client.post("/mcp", json=INIT, headers={**MCP_HEADERS, **headers})


def test_defaults_to_loopback_port_18765():
    assert mcp_server.HOST == "127.0.0.1"
    assert mcp_server.PORT == 18765


def test_refuses_to_listen_on_all_interfaces():
    env = dict(os.environ, HOMELAB_MCP_HOST="0.0.0.0")
    result = subprocess.run(
        [sys.executable, str(SERVER)],
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    assert result.returncode != 0
    assert "Refusing to listen on 0.0.0.0" in result.stderr


@pytest.mark.parametrize(
    "host,allowed",
    [
        ("127.0.0.1:18765", True),
        ("localhost:18765", True),
        ("[::1]:18765", True),
        ("mini.tail1234.ts.net:8765", True),
        ("mini.tail1234.ts.net", True),
        ("evil.example.com", False),
        ("ts.net.evil.example.com", False),
        ("192.168.1.20:18765", False),
    ],
)
def test_host_allowed(host, allowed):
    assert mcp_server.host_allowed(mcp_server._host_name(host)) is allowed


def test_http_guard_accepts_loopback_and_tailnet_rejects_others():
    with TestClient(mcp_server.build_app(), base_url="http://127.0.0.1:18765") as c:
        assert post_init(c).status_code == 200
        assert post_init(c, host="mini.tail1234.ts.net:8765").status_code == 200
        assert post_init(c, host="evil.example.com").status_code == 421
        assert post_init(c, origin="http://evil.example.com").status_code == 403


def test_every_routed_tool_is_registered():
    server = mcp_server.build_server()
    names = {tool.name for tool in asyncio.run(server.list_tools())}
    structured = {"health_check"} | set(mcp_server.homelab_tools.TOOLS)
    assert set(mcp_routing.TOOL_SCRIPTS) | {"check_port"} | structured == names


def test_slow_tool_does_not_block_other_requests(monkeypatch):
    """A tool call runs in a worker thread, so the event loop keeps serving.

    If dispatch ran on the event loop, the 0.1s sleep below couldn't finish until
    the 2s tool call returned.
    """

    def slow_dispatch(name, arguments=None):
        time.sleep(2)
        return "Result: OK (exit 0)\n"

    monkeypatch.setattr(mcp_server, "dispatch", slow_dispatch)
    server = mcp_server.build_server()

    async def scenario():
        call = asyncio.create_task(server.call_tool("check_storage", {}))
        t0 = time.monotonic()
        await asyncio.sleep(0.1)  # the tool call starts during this sleep
        elapsed = time.monotonic() - t0
        await call
        return elapsed

    assert asyncio.run(scenario()) < 1.0
