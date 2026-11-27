"""Read config/homelab.env (and homelab.local.env) with the standard library.

The generated files bash sources: KEY="value" lines, with backslash, double
quote, dollar and backtick escaped by a backslash, and a leading $HOME/ for
the home folder. This module imports nothing outside the standard library, so
anything can use it, however broken the environment.
"""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Optional

CONFIG_DIR = Path(__file__).resolve().parents[1] / "config"
LINE = re.compile(r'^(HOMELAB_[A-Z0-9_]+)="(.*)"$')


def parse_env(text: str, home: Optional[str] = None) -> dict[str, str]:
    home = home if home is not None else os.path.expanduser("~")
    values = {}
    for line in text.splitlines():
        m = LINE.match(line)
        if not m:
            continue
        raw = m.group(2)
        value = re.sub(r"\\([\\\"$`])", r"\1", raw)
        if raw.startswith("$HOME/"):
            value = os.path.join(home, value[len("$HOME/") :])
        values[m.group(1)] = value
    return values


def read_env_file(config_dir: Path = CONFIG_DIR) -> dict[str, str]:
    """homelab.env, then homelab.local.env over it; missing files are empty."""
    values: dict[str, str] = {}
    for name in ("homelab.env", "homelab.local.env"):
        try:
            values.update(parse_env((config_dir / name).read_text(encoding="utf-8")))
        except OSError:
            pass
    return values
