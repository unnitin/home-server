"""Ports on the mini, and Tailscale: connected, mappings as the manifest says."""

from __future__ import annotations

import socket
import time
from typing import Any

from homelab import config
from homelab import result as R
from homelab.adapters import tailscale

LOCAL_HOSTS = {"localhost", "127.0.0.1", "::1"}


def _owner(m: config.Manifest, port: int) -> str:
    for name, svc in m.services.items():
        if port in svc.all_ports():
            return name
    for mp in m.remote_access.tailscale_serve:
        if mp.https == port:
            return f"{mp.service} (tailnet)"
    return ""


def check_port(port: int, host: str = "localhost") -> dict:
    """TCP connect to a port on the mini itself (never another machine)."""
    if host not in LOCAL_HOSTS:
        return R.error(
            f"only the mini's own ports are checked ({', '.join(sorted(LOCAL_HOSTS))})"
        )
    if not 1 <= int(port) <= 65535:
        return R.error(f"not a port: {port}")
    m = config.load()
    started = time.monotonic()
    try:
        with socket.create_connection((host, int(port)), timeout=2):
            open_ = True
            detail = ""
    except OSError as err:
        open_ = False
        detail = err.strerror or str(err)
    ms = int((time.monotonic() - started) * 1000)
    owner = _owner(m, int(port))
    label = f"{host}:{port}" + (f" ({owner})" if owner else "")
    check = R.check(
        f"network.port.{port}",
        "ok" if open_ else "fail",
        f"{label} {'accepts connections' if open_ else 'refused: ' + detail}",
        "network",
    )
    return R.make(
        [check],
        {
            "host": host,
            "port": int(port),
            "open": open_,
            "service": owner or None,
            "ms": ms,
        },
        summary=check["message"],
        verbose=True,
    )


def tailscale_status() -> dict:
    m = config.load()
    st = tailscale.status()
    checks = []
    data: dict[str, Any] = {"installed": st.installed}
    if not st.installed:
        return R.make(
            [
                R.check(
                    "tailscale.installed",
                    "fail",
                    "Tailscale isn't installed",
                    "tailscale",
                )
            ],
            data,
        )
    data |= {
        "backend": st.backend,
        "connected": st.connected,
        "dns_name": st.dns_name,
        "ip": next((ip for ip in st.ips if "." in ip), None),
        "version": st.version,
        "peers": {"total": st.peers, "online": st.peers_online},
        "cert_domains": list(st.cert_domains),
    }
    checks.append(
        R.check(
            "tailscale.connected",
            "ok" if st.connected else "fail",
            f"connected as {st.dns_name}"
            if st.connected
            else f"not connected ({st.backend or 'no answer'})",
            "tailscale",
        )
    )
    for h in st.health:
        checks.append(R.check("tailscale.health", "warn", h[:150], "tailscale"))
    wanted = {mp.https: mp.target for mp in m.remote_access.tailscale_serve}
    service_of = {mp.https: mp.service for mp in m.remote_access.tailscale_serve}
    live = tailscale.serve()
    if live is None:
        checks.append(
            R.check("tailscale.serve", "warn", "serve status unreadable", "tailscale")
        )
    else:
        d = tailscale.drift(live, wanted)
        served = {mp.https: mp.target for mp in live}
        data["mappings"] = [
            {
                "https": port,
                "service": service_of[port],
                "target": wanted[port],
                "served": port in served,
            }
            for port in sorted(wanted)
        ]
        for port in d.missing:
            checks.append(
                R.check(
                    f"tailscale.serve.{port}",
                    "fail",
                    f"tailnet :{port} ({service_of[port]}) is not served",
                    "tailscale",
                )
            )
        for port, have, want in d.wrong:
            checks.append(
                R.check(
                    f"tailscale.serve.{port}",
                    "fail",
                    f"tailnet :{port} goes to {have}, not {want}",
                    "tailscale",
                )
            )
        for port in d.extra:
            checks.append(
                R.check(
                    f"tailscale.serve.{port}",
                    "warn",
                    f"tailnet :{port} is served but not in the manifest",
                    "tailscale",
                )
            )
        for port in d.funnel:
            checks.append(
                R.check(
                    f"tailscale.funnel.{port}",
                    "fail",
                    f":{port} is on Funnel: reachable from the internet",
                    "tailscale",
                )
            )
        if d.clean:
            checks.append(
                R.check(
                    "tailscale.serve",
                    "ok",
                    f"all {len(wanted)} tailnet mappings match the manifest",
                    "tailscale",
                )
            )
    return R.make(
        checks,
        data,
        ok_summary=f"Tailscale connected; {len(wanted)} mappings as the manifest says",
    )
