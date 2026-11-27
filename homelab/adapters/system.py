"""Power settings, uptime, macOS version and SMART health (read-only)."""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from typing import Optional

from homelab import exec as hexec


def pmset() -> dict[str, str]:
    """`pmset -g`: setting -> value (the first word; any note after it is dropped)."""
    r = hexec.run(["pmset", "-g"])
    out = {}
    for line in r.stdout.splitlines():
        m = re.match(r"^\s+([A-Za-z][A-Za-z ]*?)\s{2,}(\S+)", line) or re.match(
            r"^\s+(\S+)\s+(\S+)", line
        )
        if m:
            out[m.group(1).strip()] = m.group(2)
    return out


def sleep_preventers() -> list[str]:
    """What `pmset -g` says is keeping the mini awake, e.g. caffeinate."""
    r = hexec.run(["pmset", "-g"])
    m = re.search(r"sleep prevented by ([^)]*)\)", r.stdout)
    return [p.strip() for p in m.group(1).split(",")] if m else []


def boot_time() -> Optional[float]:
    r = hexec.run(["sysctl", "-n", "kern.boottime"])
    m = re.search(r"sec = (\d+)", r.stdout)
    return float(m.group(1)) if m else None


def uptime_s(now: Optional[float] = None) -> Optional[int]:
    booted = boot_time()
    return None if booted is None else int((now or time.time()) - booted)


def macos_version() -> str:
    return hexec.run(["sw_vers", "-productVersion"]).stdout.strip()


@dataclass(frozen=True)
class Smart:
    device: str
    supported: bool
    passed: Optional[bool] = None
    temperature_c: Optional[int] = None
    power_on_hours: Optional[int] = None
    percentage_used: Optional[int] = None  # NVMe wear
    media_errors: Optional[int] = None
    message: str = ""


def smart(disk: str) -> Smart:
    """SMART for a whole disk (disk6). USB bridges often can't pass it through."""
    if not hexec.available("smartctl"):
        return Smart(disk, supported=False, message="smartctl not installed")
    r = hexec.run(["smartctl", "-a", "--json", f"/dev/{disk}"], timeout=30)
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        return Smart(disk, supported=False, message="no SMART output")
    status = data.get("smart_status")
    if status is None:
        msgs = [
            m.get("string", "")
            for m in (data.get("smartctl") or {}).get("messages", [])
        ]
        return Smart(disk, supported=False, message="; ".join(msgs)[:200])
    nvme = data.get("nvme_smart_health_information_log") or {}
    return Smart(
        device=disk,
        supported=True,
        passed=bool(status.get("passed")),
        temperature_c=(data.get("temperature") or {}).get("current"),
        power_on_hours=(data.get("power_on_time") or {}).get("hours"),
        percentage_used=nvme.get("percentage_used"),
        media_errors=nvme.get("media_errors"),
    )
