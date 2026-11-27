"""The read-only (T0) tools, by name: what the MCP server and the CLI both call.

`call` never raises: a bug or an unexpected state becomes an error result
that says what failed, so a client always gets an envelope back.
"""

from __future__ import annotations

import sys
import traceback
from typing import Any, Callable

from homelab import result as R
from homelab.domains import health, logs, media, network, photos, services
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
}


def call(name: str, **kwargs: Any) -> dict[str, Any]:
    if name not in TOOLS:
        return R.error(f"unknown tool {name!r}")
    try:
        return TOOLS[name](**kwargs)
    except Exception as err:  # every failure becomes a result, never a crash
        traceback.print_exc(file=sys.stderr)
        return R.error(f"{name} failed: {type(err).__name__}: {err}")
