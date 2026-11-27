"""system_overview: every service and tier in one small result.

Built on the domains (adapters, not diagnostics), in parallel. It's the first
call for any "is everything OK?" question: under 2 KB unless verbose, the
worst problems first, and a hint toward the tool that digs deeper.
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from typing import Any

from homelab import result as R
from homelab.domains import network, services, storage, system

MAX_CHECKS = 8


def overview(verbose: bool = False) -> dict:
    with ThreadPoolExecutor(max_workers=4) as pool:
        parts = {
            "storage": pool.submit(storage.status, "all", True, False),
            "services": pool.submit(services.status, "all", True),
            "tailscale": pool.submit(network.tailscale_status),
            "power": pool.submit(system.power_status),
        }
        res = {k: f.result() for k, f in parts.items()}

    checks: list[dict] = []
    for part in res.values():
        checks += part["checks"]
        if part["status"] == "error":
            checks.append(
                R.check("overview.error", "error", part["summary"], "overview")
            )

    tiers: dict[str, Any] = {}
    for name, t in (res["storage"]["data"].get("tiers") or {}).items():
        raid = t.get("raid") or {}
        tiers[name] = {
            "mounted": t["mounted"],
            "raid": raid.get("status"),
            "used_pct": (t.get("usage") or {}).get("used_pct"),
        }
    svc_states = {
        n: v["state"]
        for n, v in (res["services"]["data"].get("services") or {}).items()
    }
    ts = res["tailscale"]["data"]
    data = {
        "tiers": tiers,
        "services": svc_states,
        "tailnet": {
            "connected": ts.get("connected"),
            "mappings_ok": res["tailscale"]["status"] == "ok",
        },
        "power": {"sleep": res["power"]["data"].get("settings", {}).get("sleep")},
    }

    hints = []
    for part, tool in (
        ("storage", "storage_status()"),
        ("services", "service_status(service='all')"),
        ("tailscale", "tailscale_status()"),
        ("power", "power_status()"),
    ):
        if res[part]["status"] != "ok":
            hints += [h for h in res[part]["hints"] if "truncated" not in h][:1] or [
                tool
            ]
    up = sum(1 for s in svc_states.values() if s == "up")
    mounted = sum(1 for t in tiers.values() if t["mounted"])
    return R.make(
        checks,
        data,
        ok_summary=f"All good: {up} services up, {mounted} tiers mounted",
        hints=hints[:4],
        verbose=verbose,
        max_checks=MAX_CHECKS,
    )
