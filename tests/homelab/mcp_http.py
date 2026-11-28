"""A minimal MCP client over the server's HTTP app, for tests (no network)."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Optional

import pytest

REPO = Path(__file__).resolve().parents[2]


def server_module():
    pytest.importorskip("mcp.server.fastmcp")
    if str(REPO / "homelab_mcp") not in sys.path:
        sys.path.insert(0, str(REPO / "homelab_mcp"))
    import mcp_server

    return mcp_server


class Session:
    """initialize, then JSON-RPC requests with the session id and a token."""

    def __init__(self, client, token: Optional[str], **headers: str):
        self.client = client
        self.headers = {"accept": "application/json, text/event-stream", **headers}
        if token:
            self.headers["authorization"] = f"Bearer {token}"
        self.next_id = 1
        self.init = self.post(
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "pytest", "version": "1"},
            },
        )
        sid = self.last.headers.get("mcp-session-id")
        if sid:
            self.headers["mcp-session-id"] = sid
            self.client.post(
                "/mcp",
                json={"jsonrpc": "2.0", "method": "notifications/initialized"},
                headers=self.headers,
            )

    def post(self, method: str, params: Optional[dict] = None) -> Any:
        body = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            body["params"] = params
        self.next_id += 1
        self.last = self.client.post("/mcp", json=body, headers=self.headers)
        if self.last.status_code != 200:
            return None
        text = self.last.text
        if self.last.headers.get("content-type", "").startswith("application/json"):
            return json.loads(text)
        for line in text.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip())
        return None

    def tools(self) -> list[str]:
        return sorted(t["name"] for t in self.post("tools/list")["result"]["tools"])

    def call(self, name: str, **args: Any) -> dict:
        return self.post("tools/call", {"name": name, "arguments": args})["result"]
