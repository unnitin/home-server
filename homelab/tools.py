"""The tools, by name: what the MCP server and the CLI both call.

TOOLS only look (T0). WRITES add to the state database: notes and incident
records, never anything on the system itself.

`call` never raises: a bug or an unexpected state becomes an error result
that says what failed, so a client always gets an envelope back.
"""

from __future__ import annotations

import sys
import traceback
from typing import Any, Callable

from homelab import result as R
from homelab.domains import context, health, logs, media, memory, network, photos
from homelab.domains import services
from homelab.domains import storage, system, updates

TOOLS: dict[str, Callable[..., dict[str, Any]]] = {
    "system_overview": health.overview,
    "storage_status": storage.status,
    "storage_plan_recovery": storage.plan_recovery,
    "service_status": services.status,
    "launchd_jobs": services.launchd_jobs,
    "docker_containers": services.docker_containers,
    "service_logs": logs.service_logs,
    "logs_search": logs.logs_search,
    "network_check_port": network.check_port,
    "tailscale_status": network.tailscale_status,
    "power_status": system.power_status,
    "config_get": system.config_get,
    "media_staging_list": media.staging_list,
    "media_library_stats": media.library_stats,
    "photos_stats": photos.stats,
    "updates_check": updates.check,
    "history_query": memory.history_query,
    "incident_list": memory.incident_list,
    "memory_recall": memory.memory_recall,
    "docs_search": context.docs_search,
    "runbook_get": context.runbook_get,
}

# Tools that write to the state database (notes, incidents), never the system.
WRITES: dict[str, Callable[..., dict[str, Any]]] = {
    "incident_open": memory.incident_open,
    "incident_update": memory.incident_update,
    "incident_resolve": memory.incident_resolve,
    "memory_note": memory.memory_note,
    "memory_forget": memory.memory_forget,
}
ALL = {**TOOLS, **WRITES}


def call(name: str, **kwargs: Any) -> dict[str, Any]:
    if name not in ALL:
        return R.error(f"unknown tool {name!r}")
    try:
        return ALL[name](**kwargs)
    except Exception as err:  # every failure becomes a result, never a crash
        traceback.print_exc(file=sys.stderr)
        return R.error(f"{name} failed: {type(err).__name__}: {err}")
