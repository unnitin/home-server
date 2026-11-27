#!/usr/bin/env python3
"""Probe the MCP server's Phase 2 surface, inside the VM. Prints one JSON object.

  mcp_probe.py URL
"""

import asyncio
import json
import sys

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


async def main(url: str) -> dict:
    out: dict = {}
    async with streamablehttp_client(url) as (r, w, _):
        async with ClientSession(r, w) as s:
            init = await s.initialize()
            out["instructions_words"] = len((init.instructions or "").split())
            tools = (await s.list_tools()).tools
            out["tools"] = sorted(t.name for t in tools)
            calls = {
                "system_overview": {},
                "storage_status": {"tier": "faststore"},
                "incident_list": {"status": "all"},
                "history_query": {"metric": "storage.faststore.mounted", "since": "1d"},
                "docs_search": {"query": "raid degraded"},
                "launchd_jobs": {},
            }
            out["calls"] = {}
            for name, args in calls.items():
                res = await s.call_tool(name, args)
                sc = res.structuredContent or {}
                out["calls"][name] = {
                    "is_error": res.isError,
                    "status": sc.get("status"),
                    "summary": sc.get("summary"),
                    "bytes": len(json.dumps(sc)),
                }
            res = await s.list_resources()
            out["resources"] = sorted(str(x.uri) for x in res.resources)
            out["prompts"] = sorted(p.name for p in (await s.list_prompts()).prompts)
    return out


if __name__ == "__main__":
    print(json.dumps(asyncio.run(main(sys.argv[1])), indent=2))
