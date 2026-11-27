"""Power settings against the manifest's 24/7 profile, and the manifest itself."""

from __future__ import annotations

from typing import Optional

from homelab import config
from homelab import result as R
from homelab.adapters import system

SECTIONS = [
    "host",
    "storage",
    "services",
    "boot_order",
    "remote_access",
    "media",
    "photos",
    "power",
]


def power_status() -> dict:
    m = config.load()
    live = system.pmset()
    want = m.power.model_dump()
    checks = []
    for setting, value in want.items():
        have = live.get(setting)
        if have is None:
            continue  # not every Mac has every setting
        ok = have == str(value)
        level = (
            "ok" if ok else ("fail" if setting in ("sleep", "disksleep") else "warn")
        )
        checks.append(
            R.check(
                f"power.{setting}",
                level,
                f"{setting} is {have}" + ("" if ok else f" (want {value})"),
                "power",
            )
        )
    up = system.uptime_s()
    data = {
        "settings": {k: live.get(k) for k in want},
        "wanted": want,
        "autorestart": live.get("autorestart"),
        "sleep_prevented_by": system.sleep_preventers(),
        "uptime_days": round(up / 86400, 1) if up is not None else None,
        "macos": system.macos_version(),
    }
    hints = []
    if live.get("autorestart") == "0":
        hints.append(
            "autorestart is 0: after a power cut the mini stays off until "
            "someone presses the button"
        )
    return R.make(
        checks, data, ok_summary="Power settings match the 24/7 profile", hints=hints
    )


def config_get(section: Optional[str] = None) -> dict:
    m = config.load()
    data = m.model_dump(mode="json", exclude_none=True)
    if section:
        if section not in SECTIONS:
            return R.error(
                f"unknown section {section!r}; use one of {', '.join(SECTIONS)}"
            )
        data = {section: data[section]}
    return R.make(
        [], data, summary=f"manifest {section or 'in full'} (config/homelab.yaml)"
    )
