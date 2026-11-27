"""LaunchD jobs in the user's GUI domain, from `launchctl print` (read-only)."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Optional

from homelab import exec as hexec


def domain() -> str:
    return f"gui/{os.getuid()}"


@dataclass(frozen=True)
class Job:
    label: str
    loaded: bool
    disabled: bool = False
    state: str = ""  # running, waiting, not running …
    pid: Optional[int] = None
    last_exit: Optional[int] = None  # None: never exited
    runs: int = 0
    interval: Optional[int] = None  # StartInterval, seconds
    keepalive: bool = False

    @property
    def running(self) -> bool:
        return self.pid is not None

    @property
    def held(self) -> bool:
        """Disabled with `launchctl disable`: kept from loading on purpose."""
        return self.disabled and not self.loaded

    @property
    def failed(self) -> bool:
        return self.last_exit not in (None, 0)


TOP = re.compile(r"^\t([a-z][a-z ]*?) = (.*)$")


def parse_print(label: str, text: str) -> Job:
    """The top-level `key = value` lines of `launchctl print` for one job."""
    fields: dict[str, str] = {}
    for line in text.splitlines():
        m = TOP.match(line)
        if m:
            fields.setdefault(m.group(1), m.group(2).strip())
    exit_text = fields.get("last exit code", "")
    exit_code = int(exit_text) if re.fullmatch(r"-?\d+", exit_text) else None
    pid = fields.get("pid")
    interval = re.search(r"run interval = (\d+) seconds", text)
    return Job(
        label=label,
        loaded=True,
        state=fields.get("state", ""),
        pid=int(pid) if pid and pid.isdigit() else None,
        last_exit=exit_code,
        runs=int(fields.get("runs", "0") or 0),
        interval=int(interval.group(1)) if interval else None,
        keepalive="keepalive" in fields.get("properties", ""),
    )


def disabled() -> dict[str, bool]:
    """Label -> disabled, from `launchctl print-disabled`."""
    r = hexec.run(["launchctl", "print-disabled", domain()])
    out = {}
    for m in re.finditer(r'"([^"]+)" => (enabled|disabled|true|false)', r.stdout):
        out[m.group(1)] = m.group(2) in ("disabled", "true")
    return out


def job(label: str, held: Optional[dict[str, bool]] = None) -> Job:
    """One job's state. A job launchd doesn't know is `loaded=False`."""
    held = disabled() if held is None else held
    r = hexec.run(["launchctl", "print", f"{domain()}/{label}"])
    if not r.ok:
        return Job(label=label, loaded=False, disabled=held.get(label, False))
    parsed = parse_print(label, r.stdout)
    return Job(**{**parsed.__dict__, "disabled": held.get(label, False)})


def jobs(labels: list[str]) -> list[Job]:
    held = disabled()
    return [job(label, held) for label in labels]
