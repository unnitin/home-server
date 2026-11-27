"""`python3 -m homelab ...`: the control plane's command line.

python3 -m homelab config validate        check config/homelab.yaml (+ local overrides)
python3 -m homelab config render [--check] write (or check) generated files
python3 -m homelab config get [SECTION]   print the manifest, or a section, as JSON
python3 -m homelab secrets list           which API secrets are set (never their values)
python3 -m homelab secrets set NAME       store one in the Keychain (not echoed)
python3 -m homelab secrets import-plex    copy Plex's own token into the Keychain
python3 -m homelab status [--json]         the system overview
python3 -m homelab tool NAME [KEY=VALUE…]  run any tool; `tool --list`
python3 -m homelab snapshot               record one snapshot (io.homelab.snapshot)
python3 -m homelab history METRIC [--since 7d] [--above N]
python3 -m homelab incidents [--all]
"""

from __future__ import annotations

import argparse
import getpass
import json
import sys
from pathlib import Path
from typing import Optional

from pydantic import ValidationError

from homelab import config, secrets

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


def secret_names(config_dir: Path) -> dict[str, str]:
    """Secret name -> the service that uses it, from the manifest."""
    services = config.load(config_dir).services
    return {s.api.secret: name for name, s in services.items() if s.api}


def cmd_secrets_list(args: argparse.Namespace) -> int:
    for secret, service in sorted(secret_names(args.config_dir).items()):
        state = "set" if secrets.get(secret) else "not set"
        print(f"{secret:<20} {service:<10} {state}")
    return 0


def cmd_secrets_set(args: argparse.Namespace) -> int:
    known = secret_names(args.config_dir)
    if args.name not in known:
        print(f"unknown secret {args.name!r}; the manifest's: {', '.join(known)}")
        return 2
    value = getpass.getpass(f"{args.name} for {known[args.name]} (not echoed): ")
    secrets.store(args.name, value.strip())
    print(f"stored {args.name} in the login Keychain (service: {secrets.SERVICE})")
    return 0


def cmd_secrets_import_plex(args: argparse.Namespace) -> int:
    token = secrets.plex_token_from_preferences()
    if token is None:
        print("no PlexOnlineToken in Plex's preferences: sign the server in first")
        return 1
    secrets.store("plex_token", token)
    print("stored plex_token in the login Keychain")
    return 0


def _value(text: str):
    """KEY=VALUE values: true/false, integers, a,b lists, else text."""
    if text.lower() in ("true", "false"):
        return text.lower() == "true"
    if text.lstrip("-").isdigit():
        return int(text)
    if "," in text:
        return [part for part in text.split(",") if part]
    return text


def render_text(res: dict) -> str:
    lines = [f"{res['status'].upper()}: {res['summary']}"]
    lines += [f"  [{c['status']}] {c['message']}" for c in res["checks"]]
    lines += [f"  next: {h}" for h in res["hints"]]
    return "\n".join(lines)


def cmd_status(args: argparse.Namespace) -> int:
    from homelab import tools

    res = tools.call("system_overview", verbose=args.verbose)
    print(json.dumps(res, indent=2) if args.json else render_text(res))
    return 0 if res["status"] == "ok" else 1


def cmd_tool(args: argparse.Namespace) -> int:
    import inspect

    from homelab import tools

    if args.list or not args.name:
        for name, fn in tools.ALL.items():
            doc = (fn.__doc__ or "").strip().splitlines()
            print(f"{name:<24} {doc[0] if doc else ''}")
        return 0
    kwargs = {}
    for pair in args.params:
        key, sep, value = pair.partition("=")
        if not sep:
            print(f"parameters are KEY=VALUE: {pair!r}", file=sys.stderr)
            return 2
        kwargs[key] = _value(value)
    fn = tools.ALL.get(args.name)
    if fn is not None and "actor" in inspect.signature(fn).parameters:
        kwargs.setdefault("actor", "cli")
    res = tools.call(args.name, **kwargs)
    print(json.dumps(res, indent=2))
    return 0 if res["status"] in ("ok", "warn") else 1


def cmd_snapshot(args: argparse.Namespace) -> int:
    from homelab.state import snapshot

    out = snapshot.take()
    print(json.dumps(out))
    return 0


def cmd_history(args: argparse.Namespace) -> int:
    from homelab import tools

    res = tools.call(
        "history_query", metric=args.metric, since=args.since, above=args.above
    )
    print(json.dumps(res, indent=2) if args.json else render_text(res))
    return 0 if res["status"] != "error" else 1


def cmd_incidents(args: argparse.Namespace) -> int:
    from homelab import tools

    res = tools.call("incident_list", status="all" if args.all else "open")
    if res["status"] == "error":
        print(render_text(res))
        return 1
    for row in res["data"]["incidents"]["content"]:
        closed = f" -> {row['closed']}" if row["closed"] else ""
        print(f"#{row['id']} [{row['status']}] {row['component']}: {row['title']}")
        print(f"    {row['opened']}{closed}")
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

    sec = top.add_parser("secrets", help="service API secrets in the Keychain")
    sub = sec.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="which are set").set_defaults(fn=cmd_secrets_list)
    put = sub.add_parser("set", help="store one (you're asked for the value)")
    put.add_argument("name")
    put.set_defaults(fn=cmd_secrets_set)
    sub.add_parser(
        "import-plex", help="copy Plex Media Server's own token into the Keychain"
    ).set_defaults(fn=cmd_secrets_import_plex)

    st = top.add_parser("status", help="the system overview")
    st.add_argument("--json", action="store_true")
    st.add_argument(
        "--verbose", action="store_true", help="every check, not just problems"
    )
    st.set_defaults(fn=cmd_status)
    tl = top.add_parser("tool", help="run a read-only tool, as the MCP server does")
    tl.add_argument("name", nargs="?")
    tl.add_argument("params", nargs="*", metavar="KEY=VALUE")
    tl.add_argument("--list", action="store_true")
    tl.set_defaults(fn=cmd_tool)
    top.add_parser("snapshot", help="record one snapshot").set_defaults(fn=cmd_snapshot)
    hi = top.add_parser("history", help="a metric's history")
    hi.add_argument("metric")
    hi.add_argument("--since", default="7d")
    hi.add_argument("--above", type=float)
    hi.add_argument("--json", action="store_true")
    hi.set_defaults(fn=cmd_history)
    inc = top.add_parser("incidents", help="open incidents (--all for every one)")
    inc.add_argument("--all", action="store_true")
    inc.set_defaults(fn=cmd_incidents)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args)
    except (ValidationError, ValueError, OSError, RuntimeError) as err:
        print(f"homelab: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
