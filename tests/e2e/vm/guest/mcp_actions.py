#!/usr/bin/env python3
"""Drive the Phase 3 surface over MCP, inside the VM. Prints one JSON object.

  mcp_actions.py scopes URL OBSERVE_TOKEN OPS_TOKEN
      what each scope sees and may call; an action's default is a dry run
  mcp_actions.py call URL TOKEN TOOL [JSON_ARGS]
      one call: status, summary, job_id, data
  mcp_actions.py wait URL TOKEN JOB_ID [TIMEOUT]
      poll job_status until the job finishes
  mcp_actions.py audit URL TOKEN
      audit_recent: who called what
"""

import asyncio
import json
import sys
import time

from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client as client

T1 = {
    "service_restart",
    "service_start",
    "media_process",
    "power_ensure",
    "logs_collect",
    "memory_note",
}


async def session(url, token, fn):
    headers = {"Authorization": f"Bearer {token}"}
    async with client(url, headers=headers) as (r, w, _):
        async with ClientSession(r, w) as s:
            await s.initialize()
            return await fn(s)


def envelope(res) -> dict:
    sc = res.structuredContent or {}
    text = " ".join(getattr(c, "text", "") for c in res.content or [])
    return {
        "is_error": res.isError,
        "status": sc.get("status"),
        "summary": sc.get("summary") or text[:300],
        "job_id": sc.get("job_id"),
        "data": sc.get("data"),
    }


async def scopes(url, observe, ops):
    async def look(s):
        names = sorted(t.name for t in (await s.list_tools()).tools)
        restart = envelope(
            await s.call_tool("service_restart", {"service": "jellyfin"})
        )
        return {
            "tools": names,
            "t1_seen": sorted(T1 & set(names)),
            "restart_default": restart,
        }

    return {
        "observe": await session(url, observe, look),
        "ops": await session(url, ops, look),
    }


async def call(url, token, tool, args):
    async def go(s):
        return envelope(await s.call_tool(tool, args))

    return await session(url, token, go)


async def wait(url, token, job_id, timeout):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = await call(url, token, "job_status", {"job_id": job_id})
        except Exception as err:  # the server may be restarting
            last = {"error": str(err)}
        job = ((last or {}).get("data") or {}).get("job") or {}
        if job.get("state") in ("done", "failed", "cancelled", "lost"):
            return {
                "job": job,
                "waited_s": round(timeout - (deadline - time.monotonic())),
            }
        await asyncio.sleep(3)
    return {"timeout": True, "last": last}


async def main(argv):
    mode, url = argv[1], argv[2]
    if mode == "scopes":
        return await scopes(url, argv[3], argv[4])
    if mode == "call":
        args = json.loads(argv[5]) if len(argv) > 5 else {}
        return await call(url, argv[3], argv[4], args)
    if mode == "wait":
        return await wait(
            url, argv[3], argv[4], float(argv[5]) if len(argv) > 5 else 240
        )
    if mode == "audit":
        return await call(url, argv[3], "audit_recent", {"limit": 100, "since": "1d"})
    raise SystemExit(f"unknown mode {mode}")


if __name__ == "__main__":
    print(json.dumps(asyncio.run(main(sys.argv)), indent=2, default=str))
