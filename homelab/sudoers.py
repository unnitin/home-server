"""The scoped sudo rule (docs/mcp-refactor/05, "Sudo").

The control plane never gets general sudo. /etc/sudoers.d/homelab, installed
by scripts/core/install_sudoers.sh (as root, after `visudo -c`), allows the
mini's user exactly these commands without a password, and nothing else:

- `/usr/bin/pmset -a <setting> <value>` for each setting of the manifest's
  power profile, with its value. Nothing else in pmset, no other value.

No wildcards: in sudoers a `*` also matches spaces, so `pmset -a sleep *` would
allow `pmset -a sleep 0 hibernatemode 3`. diskutil has no rule at all, so the
T3 boundary is enforced by the OS as well. `tailscale serve` needs no sudo on
this mini (the CLI talks to the Tailscale app as the user).

homelab.exec allows `sudo -n …` only for these same argv lists, so the file and
the code can't drift apart: both come from `rules()`. Change the power profile
and the rule must be installed again; `homelab sudoers check` says so, from the
NOPASSWD entries `sudo -n -l` lists.
"""

from __future__ import annotations

import getpass
import os
import re
from typing import Optional

from homelab import config

PMSET = "/usr/bin/pmset"
SUDOERS_FILE = "/etc/sudoers.d/homelab"
POWER_SETTINGS = ("sleep", "displaysleep", "disksleep", "womp", "powernap", "standby")


def rules(m: Optional[config.Manifest] = None) -> list[list[str]]:
    """Every command the rule allows, as an argv list (absolute paths)."""
    m = m or config.load()
    power = m.power.model_dump()
    return [[PMSET, "-a", key, str(int(power[key]))] for key in POWER_SETTINGS]


def allowed(argv: list[str], m: Optional[config.Manifest] = None) -> bool:
    return list(argv) in rules(m)


def render(user: Optional[str] = None, m: Optional[config.Manifest] = None) -> str:
    user = user or os.environ.get("SUDO_USER") or getpass.getuser()
    if not user.replace("-", "").replace("_", "").replace(".", "").isalnum():
        raise ValueError(f"unexpected user name {user!r}")
    commands = ", \\\n    ".join(" ".join(r) for r in rules(m))
    return (
        "# /etc/sudoers.d/homelab: written by scripts/core/install_sudoers.sh from\n"
        "# config/homelab.yaml (power:). Exact commands only, no wildcards; diskutil\n"
        "# has no rule. Re-run the script after changing the power profile.\n"
        # Each command spelled out, not behind a Cmnd_Alias, so `sudo -l`
        # lists them and `homelab sudoers check` can read them back.
        f"{user} ALL = (root) NOPASSWD: \\\n    {commands}\n"
    )


def nopasswd_commands(listing: str) -> set[str]:
    """The commands `sudo -l` says run without a password.

    `sudo -l` prints one entry per line, like `    (root) NOPASSWD: /a b, /c d`
    (other tags such as SETENV: may follow NOPASSWD:). Only entries tagged
    NOPASSWD count: an admin may run anything *with* a password, which is
    what `sudo -n -l CMD` would wrongly report as allowed.
    """
    found: set[str] = set()
    for line in listing.splitlines():
        m = re.match(r"^\s*\([^)]*\)\s+(.*)$", line)
        if not m or "NOPASSWD:" not in m.group(1):
            continue
        rest = m.group(1).split("NOPASSWD:", 1)[1]
        rest = re.sub(r"^\s*(?:[A-Z_]+:\s*)*", "", rest)  # SETENV: and the like
        found |= {c.strip() for c in rest.split(",") if c.strip()}
    return found


def missing(listing: str, m: Optional[config.Manifest] = None) -> list[str]:
    """The rule's commands that don't run without a password, per `sudo -l`."""
    have = nopasswd_commands(listing)
    return [" ".join(r) for r in rules(m) if " ".join(r) not in have]
