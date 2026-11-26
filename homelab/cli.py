"""`python3 -m homelab ...`: the control plane's command line.

python3 -m homelab config validate        check config/homelab.yaml (+ local overrides)
python3 -m homelab config render [--check] write (or check) the generated files
python3 -m homelab config get [SECTION]   print the manifest, or one section, as JSON
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

from pydantic import ValidationError

from homelab import config

SECTIONS = [
    "host",
    "storage",
    "services",
    "boot_order",
    "remote_access",
    "media",
    "photos",
]


def _rel(path: Path) -> str:
    try:
        return str(path.relative_to(config.REPO))
    except ValueError:
        return str(path)


def cmd_validate(args: argparse.Namespace) -> int:
    manifest = config.load(args.config_dir)
    print(
        f"OK: {len(manifest.services)} services, {len(manifest.storage.tiers)} tiers, "
        f"{len(manifest.remote_access.tailscale_serve)} tailnet mappings"
    )
    return 0


def cmd_render(args: argparse.Namespace) -> int:
    if args.check:
        stale = config.stale(args.config_dir)
        for path in stale:
            print(f"stale: {_rel(path)} (run: python3 -m homelab config render)")
        return 1 if stale else 0
    for path in config.write(args.config_dir):
        print(f"wrote {_rel(path)}")
    return 0


def cmd_get(args: argparse.Namespace) -> int:
    data = config.load(args.config_dir).model_dump(mode="json", exclude_none=True)
    print(json.dumps(data[args.section] if args.section else data, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="homelab")
    parser.add_argument(
        "--config-dir", type=Path, default=config.CONFIG_DIR, help=argparse.SUPPRESS
    )
    top = parser.add_subparsers(dest="area", required=True)
    cfg = top.add_parser("config", help="the manifest, config/homelab.yaml")
    sub = cfg.add_subparsers(dest="command", required=True)
    sub.add_parser("validate", help="check the manifest").set_defaults(fn=cmd_validate)
    render = sub.add_parser("render", help="write the files bash reads")
    render.add_argument("--check", action="store_true", help="exit 1 if any is stale")
    render.set_defaults(fn=cmd_render)
    get = sub.add_parser("get", help="print the manifest as JSON")
    get.add_argument("section", nargs="?", choices=SECTIONS)
    get.set_defaults(fn=cmd_get)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except (ValidationError, ValueError, OSError) as err:
        print(f"homelab: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
