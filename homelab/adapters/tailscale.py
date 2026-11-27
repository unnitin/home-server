"""Tailscale state, from `tailscale status --json` and `serve status --json`.

The Mac app's CLI works from a LaunchD job (it's how check_tailscale.sh
reaches it). Peer names are never returned: other people's devices can share
the tailnet, so only counts leave this module.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Optional

from homelab import exec as hexec


@dataclass(frozen=True)
class Status:
    installed: bool
    backend: str = ""  # Running, Stopped, NeedsLogin …
    online: bool = False
    dns_name: str = ""
    ips: tuple[str, ...] = ()
    version: str = ""
    peers: int = 0
    peers_online: int = 0
    cert_domains: tuple[str, ...] = ()
    health: tuple[str, ...] = ()

    @property
    def connected(self) -> bool:
        return self.backend == "Running" and self.online


@dataclass(frozen=True)
class Mapping:
    https: int
    target: str
    funnel: bool = False


def _json(argv: list[str]) -> Optional[Any]:
    r = hexec.run(argv, timeout=15)
    if not r.ok:
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None


def status() -> Status:
    if not hexec.available("tailscale"):
        return Status(installed=False)
    data = _json(["tailscale", "status", "--json"])
    if not isinstance(data, dict):
        return Status(installed=True)
    me = data.get("Self") or {}
    peers = (data.get("Peer") or {}).values()
    return Status(
        installed=True,
        backend=data.get("BackendState", ""),
        online=bool(me.get("Online")),
        dns_name=(me.get("DNSName") or "").rstrip("."),
        ips=tuple(data.get("TailscaleIPs") or me.get("TailscaleIPs") or ()),
        version=(data.get("Version") or "").split("-")[0],
        peers=len(list(peers)),
        peers_online=sum(
            1 for p in (data.get("Peer") or {}).values() if p.get("Online")
        ),
        cert_domains=tuple(data.get("CertDomains") or ()),
        health=tuple(data.get("Health") or ()),
    )


def serve() -> Optional[list[Mapping]]:
    """The live HTTPS mappings, or None if serve status can't be read."""
    if not hexec.available("tailscale"):
        return None
    data = _json(["tailscale", "serve", "status", "--json"])
    if data is None:
        return None
    if not isinstance(data, dict):
        return []
    funnel = {
        int(hp.rsplit(":", 1)[1])
        for hp, on in (data.get("AllowFunnel") or {}).items()
        if on and ":" in hp
    }
    mappings = []
    for host_port, web in (data.get("Web") or {}).items():
        port = int(host_port.rsplit(":", 1)[1])
        proxy = ((web.get("Handlers") or {}).get("/") or {}).get("Proxy", "")
        mappings.append(Mapping(https=port, target=proxy, funnel=port in funnel))
    return sorted(mappings, key=lambda m: m.https)


@dataclass(frozen=True)
class Drift:
    missing: tuple[int, ...]  # in the manifest, not served
    wrong: tuple[tuple[int, str, str], ...]  # (port, served target, wanted target)
    extra: tuple[int, ...]  # served, not in the manifest
    funnel: tuple[int, ...]  # exposed to the internet: never wanted

    @property
    def clean(self) -> bool:
        return not (self.missing or self.wrong or self.extra or self.funnel)


def drift(live: list[Mapping], wanted: dict[int, str]) -> Drift:
    """Compare live mappings with the manifest's (https port -> target URL)."""

    def norm(url: str) -> str:
        return url.rstrip("/").replace("127.0.0.1", "localhost")

    served = {m.https: m for m in live}
    return Drift(
        missing=tuple(sorted(p for p in wanted if p not in served)),
        wrong=tuple(
            (p, served[p].target, wanted[p])
            for p in sorted(wanted)
            if p in served and norm(served[p].target) != norm(wanted[p])
        ),
        extra=tuple(sorted(p for p in served if p not in wanted)),
        funnel=tuple(sorted(m.https for m in live if m.funnel)),
    )
